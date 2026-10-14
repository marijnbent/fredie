import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class MediaImportState {
    private(set) var source: MediaSource?
    private(set) var clips: [MediaClip] = []
    var selectedClipIDs: Set<String> = []
    var selectedDestinationID: UUID?
    private(set) var isScanning = false
    private(set) var scannedFileCount = 0
    private(set) var totalScanFileCount = 0
    private(set) var isImporting = false
    private(set) var completedCount = 0
    private(set) var totalImportCount = 0
    private(set) var importProgress: [String: Double] = [:]
    private var importWeights: [String: Double] = [:]

    var overallImportProgress: Double {
        let total = importWeights.values.reduce(0, +)
        guard total > 0 else { return 0 }
        return importWeights.reduce(0) { $0 + $1.value * (importProgress[$1.key] ?? 0) } / total
    }

    var activeImportCount: Int {
        clips.count { $0.status == .importing }
    }
    var alertMessage: String?
    private(set) var completionMessage: String?

    let settingsStore: MediaImportSettingsStore
    let ffmpeg: FFmpegService
    let thumbnails: ThumbnailStore
    var onRequestWindow: (() -> Void)?

    private let scan: @Sendable (MediaSource, @escaping ScanProgress) async throws -> [MediaClip]
    private var sourceGeneration = UUID()
    private let importService: ImportService
    let ledger: ImportLedger
    private var scanTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var importGeneration = UUID()
    private let isEnabled: @MainActor () -> Bool

    init(
        isEnabled: @escaping @MainActor () -> Bool,
        settingsStore: MediaImportSettingsStore = MediaImportSettingsStore(),
        ffmpeg: FFmpegService = FFmpegService(),
        ledger: ImportLedger = ImportLedger(),
        scan: (@Sendable (MediaSource, @escaping ScanProgress) async throws -> [MediaClip])? = nil
    ) {
        self.isEnabled = isEnabled
        self.settingsStore = settingsStore
        self.ffmpeg = ffmpeg
        self.ledger = ledger
        let scanner = ClipScanner(ffmpeg: ffmpeg)
        self.scan = scan ?? { try await scanner.scan($0, progress: $1) }
        thumbnails = ThumbnailStore(ffmpeg: ffmpeg)
        importService = ImportService(ffmpeg: ffmpeg)
        selectedDestinationID = settingsStore.availableLocations.first?.location.id
    }

    var selectedDestinationURL: URL? {
        let available = settingsStore.availableLocations
        if let selectedDestinationID,
           let match = available.first(where: { $0.location.id == selectedDestinationID }) {
            return match.url
        }
        return available.first?.url
    }

    var selectedCount: Int {
        clips.count { selectedClipIDs.contains($0.id) }
    }

    var totalSize: Int64 {
        clips.reduce(0) { $0 + $1.fileSize }
    }

    var deletableOriginalCount: Int {
        deletableOriginals.reduce(0) { $0 + $1.urls.count }
    }

    func prepareOriginalDeletion() -> Bool {
        guard isEnabled() else { return false }
        if let message = originalDeletionUnavailableMessage() {
            alertMessage = message
            return false
        }
        return true
    }

    private func originalDeletionUnavailableMessage() -> String? {
        guard case .folder(let sourceRoot) = source?.kind else { return nil }
        guard FileManager.default.fileExists(atPath: sourceRoot.path) else {
            return "Reconnect \(source?.name ?? "the source") before deleting its files."
        }
        let directories = Set(deletableOriginals.flatMap(\.urls).map {
            $0.deletingLastPathComponent().standardizedFileURL
        })
        guard !directories.isEmpty,
              directories.allSatisfy({ OriginalFileDeleter.isWritableDirectory($0) }) else {
            return "\(source?.name ?? "This source") is read-only. Unlock the SD card if it has a lock switch, use the camera's delete or format function, or connect it through a writable card reader."
        }
        return nil
    }

    func handleDetectedSource(_ newSource: MediaSource) {
        guard isEnabled(), !isImporting else { return }
        if case .folder = source?.kind, case .camera = newSource.kind { return }
        if source?.id == newSource.id, !clips.isEmpty { return }
        load(newSource)
        if settingsStore.openOnDetection {
            onRequestWindow?()
        }
    }

    func load(_ newSource: MediaSource) {
        guard isEnabled() else { return }
        invalidateScan()
        let generation = sourceGeneration
        source = newSource
        clips = []
        selectedClipIDs = []
        completionMessage = nil
        alertMessage = nil
        isScanning = true
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                var scanned = try await scan(newSource) { [weak self] completed, total in
                    await self?.updateScanProgress(completed: completed, total: total, generation: generation)
                }
                guard sourceGeneration == generation, !Task.isCancelled else { return }
                for index in scanned.indices {
                    if let destination = ledger.destination(for: scanned[index].fingerprint),
                       FileManager.default.fileExists(atPath: destination.path) {
                        scanned[index].status = .imported(destination)
                    }
                }
                clips = scanned
                selectedClipIDs = Set(scanned.filter { $0.status == .ready }.map(\.id))
            } catch {
                guard sourceGeneration == generation, !Task.isCancelled else { return }
                alertMessage = error.localizedDescription
            }
            scanTask = nil
            isScanning = false
        }
    }

    func handleRemovedSource(id: String) {
        guard isEnabled(), source?.id == id else { return }
        invalidateScan()
        cancelImport()
        source = nil
        clips = []
        selectedClipIDs = []
        alertMessage = "The connected source was removed."
    }

    private func updateScanProgress(completed: Int, total: Int, generation: UUID) {
        guard sourceGeneration == generation, isScanning else { return }
        scannedFileCount = completed
        totalScanFileCount = total
    }

    private func invalidateScan() {
        sourceGeneration = UUID()
        scanTask?.cancel()
        scanTask = nil
        thumbnails.cancelAll()
        scannedFileCount = 0
        totalScanFileCount = 0
        isScanning = false
    }

    func refreshDestinations() {
        settingsStore.refreshLocationAvailability()
        let availableIDs = Set(settingsStore.availableLocations.map(\.location.id))
        if let selectedDestinationID, availableIDs.contains(selectedDestinationID) {
            return
        }
        selectedDestinationID = settingsStore.availableLocations.first?.location.id
    }

    func toggleSelection(for clipID: String) {
        if selectedClipIDs.contains(clipID) {
            selectedClipIDs.remove(clipID)
        } else if let index = clips.firstIndex(where: { $0.id == clipID }) {
            if case .failed = clips[index].status {
                clips[index].status = .ready
            }
            guard clips[index].status == .ready else { return }
            selectedClipIDs.insert(clipID)
        }
    }

    func selectAllReady() {
        selectedClipIDs = Set(clips.filter { $0.status == .ready }.map(\.id))
    }

    func selectNone() {
        selectedClipIDs = []
    }

    func startImport() {
        guard isEnabled(), !isImporting, importTask == nil else { return }
        guard ffmpeg.isAvailable else {
            alertMessage = ImportieError.ffmpegMissing.localizedDescription
            return
        }
        guard let destination = selectedDestinationURL else {
            alertMessage = ImportieError.noDestination.localizedDescription
            return
        }
        let clipIDs = clips.filter { selectedClipIDs.contains($0.id) && $0.status == .ready }.map(\.id)
        guard !clipIDs.isEmpty else {
            alertMessage = ImportieError.noSelectedClips.localizedDescription
            return
        }

        isImporting = true
        importGeneration = UUID()
        importProgress = [:]
        importWeights = Dictionary(uniqueKeysWithValues: clips.filter { clipIDs.contains($0.id) }.map { ($0.id, Double(max(1, $0.fileSize))) })
        completedCount = 0
        totalImportCount = clipIDs.count
        completionMessage = nil
        alertMessage = nil
        importTask = Task { [weak self] in
            guard let self else { return }
            defer { importTask = nil }
            var successes = 0
            var failures = 0
            let concurrency = clipIDs.contains { id in
                guard let clip = clips.first(where: { $0.id == id }) else { return false }
                if case .camera = clip.origin { return true }
                return false
            } ? 1 : 4
            await withTaskGroup(of: Bool?.self) { group in
                var nextIndex = 0
                for index in 0..<min(concurrency, clipIDs.count) {
                    let id = clipIDs[index]
                    group.addTask { await self.importOne(id, to: destination) }
                    nextIndex += 1
                }
                for await result in group {
                    if let result {
                        if result { successes += 1 } else { failures += 1 }
                        completedCount += 1
                    }
                    if !Task.isCancelled, nextIndex < clipIDs.count {
                        let id = clipIDs[nextIndex]
                        group.addTask { await self.importOne(id, to: destination) }
                        nextIndex += 1
                    }
                }
            }
            isImporting = false
            if Task.isCancelled {
                completionMessage = "Import cancelled."
            } else if failures == 0 {
                completionMessage = "Imported \(successes) video\(successes == 1 ? "" : "s")."
            } else {
                completionMessage = "Imported \(successes). Failed: \(failures)."
            }
        }
    }

    private func importOne(_ clipID: String, to destination: URL) async -> Bool? {
        guard !Task.isCancelled, let index = clips.firstIndex(where: { $0.id == clipID }) else { return nil }
        clips[index].status = .importing
        let clip = clips[index]
        let generation = importGeneration
        do {
            let output = try await importService.importClip(clip, to: destination) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, self.isEnabled(), self.importGeneration == generation,
                          self.clips.contains(where: { $0.id == clipID && $0.status == .importing }) else { return }
                    self.importProgress[clipID] = max(self.importProgress[clipID] ?? 0, fraction)
                }
            }
            try ledger.record(fingerprint: clip.fingerprint, destination: output)
            if let currentIndex = clips.firstIndex(where: { $0.id == clipID }) {
                clips[currentIndex].status = .imported(output)
            }
            importProgress[clipID] = 1
            selectedClipIDs.remove(clipID)
            return true
        } catch is CancellationError {
            if let currentIndex = clips.firstIndex(where: { $0.id == clipID }) {
                clips[currentIndex].status = .ready
            }
            importProgress[clipID] = nil
            return nil
        } catch {
            if let currentIndex = clips.firstIndex(where: { $0.id == clipID }) {
                clips[currentIndex].status = .failed(error.localizedDescription)
            }
            importProgress[clipID] = 1
            selectedClipIDs.remove(clipID)
            return false
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    func stop() {
        invalidateScan()
        cancelImport()
        ffmpeg.cancelAll()
    }

    func finishStopping() async {
        await importTask?.value
    }

    func deleteImportedOriginals() {
        guard isEnabled(), !isImporting, case .folder(let sourceRoot) = source?.kind else { return }
        if let message = originalDeletionUnavailableMessage() {
            alertMessage = message
            return
        }
        let originals = deletableOriginals
        guard !originals.isEmpty else { return }

        let result = OriginalFileDeleter.delete(originals.flatMap(\.urls), from: sourceRoot)
        let deletedPaths = Set(result.deleted.map(\.path))
        let deleted = originals.filter { original in
            original.urls.allSatisfy { deletedPaths.contains($0.path) }
        }
        let deletedIDs = Set(deleted.map(\.id))
        clips.removeAll { deletedIDs.contains($0.id) }
        selectedClipIDs.subtract(deletedIDs)
        try? ledger.remove(fingerprints: deleted.map(\.fingerprint))

        let count = result.deleted.count
        if count > 0 {
            completionMessage = "Deleted \(count) original video file\(count == 1 ? "" : "s") from \(source?.name ?? "the source")."
        }
        if !result.failed.isEmpty {
            let detail = result.failed[0].message
            alertMessage = "Could not delete \(result.failed.count) original video file\(result.failed.count == 1 ? "" : "s"). \(detail)"
        }
    }

    func openDestinationFolder() {
        guard let destination = selectedDestinationURL else { return }
        NSWorkspace.shared.open(destination)
    }

    private var deletableOriginals: [(id: String, fingerprint: String, urls: [URL])] {
        guard case .folder(let sourceRoot) = source?.kind else { return [] }
        return clips.compactMap { clip in
            guard case .imported = clip.status,
                  case .file(let url) = clip.origin,
                  OriginalFileDeleter.isInsideSource(url, sourceRoot: sourceRoot) else { return nil }
            let urls = ([url] + clip.companionOriginalURLs).filter {
                OriginalFileDeleter.isInsideSource($0, sourceRoot: sourceRoot)
            }
            return (clip.id, clip.fingerprint, urls)
        }
    }
}
