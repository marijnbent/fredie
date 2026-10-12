import Foundation
import Observation

@MainActor
@Observable
final class ClipboardStore {
    private(set) var items: [ClipboardItem] = []
    private(set) var error: String?
    private(set) var isLoaded = false
    let storage: ClipboardStorage
    var historyLimit: ClipboardHistoryLimit {
        didSet { applyHistoryRetention() }
    }
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSnapshot: [ClipboardItem]?

    init(storageDirectory: URL, historyLimit: ClipboardHistoryLimit = .defaultValue) {
        storage = ClipboardStorage(storageDirectory: storageDirectory)
        self.historyLimit = historyLimit
    }

    func load() async {
        do {
            let loaded = try await Task.detached(priority: .utility) { [storage] in try storage.readHistory() }.value
            items = loaded
            isLoaded = true
            error = nil
            storage.updateReferences(loaded)
            applyHistoryRetention()
        } catch { self.error = "Could not load clipboard history." }
    }

    func add(_ item: ClipboardItem) {
        guard isLoaded else { return }
        performAdd(item)
    }

    func flush() async -> Bool {
        guard isLoaded else { return false }
        scheduleHistorySave(items)
        await saveTask?.value
        return pendingSnapshot == nil && error == nil
    }

    private func scheduleHistorySave(_ snapshot: [ClipboardItem]) {
        guard isLoaded else { return }
        storage.updateReferences(snapshot)
        pendingSnapshot = snapshot
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            guard let self else { return }
            defer { saveTask = nil }
            while let snapshot = pendingSnapshot {
                pendingSnapshot = nil
                do {
                    try await Task.detached(priority: .utility) { [storage] in try storage.writeHistory(snapshot) }.value
                    error = nil
                } catch {
                    if pendingSnapshot == nil { pendingSnapshot = snapshot }
                    self.error = "Could not save clipboard history."
                    return
                }
            }
        }
    }
    private func performAdd(_ item: ClipboardItem) {
        storage.invalidateCachedFullText(for: item.id)
        storage.invalidateCachedSearchText(for: item.id)

        items.insert(item, at: 0)

        applyHistoryRetention(persist: false)


        scheduleHistorySave(items)
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        storage.invalidateCachedFullText(for: item.id)
        storage.invalidateCachedSearchText(for: item.id)
        storage.queueFileDeletions([item])

        scheduleHistorySave(items)
    }

    func setOCRText(_ text: String, for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[index].ocrText != text else { return }

        var updatedItems = items
        updatedItems[index].ocrText = text
        items = updatedItems

        scheduleHistorySave(updatedItems)
    }

    func moveToTop(_ item: ClipboardItem, timestamp: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        var updatedItems = items
        var updatedItem = updatedItems.remove(at: index)
        updatedItem = ClipboardItem(
            id: updatedItem.id,
            type: updatedItem.type,
            timestamp: timestamp,
            sourceApp: updatedItem.sourceApp,
            sourceBundleIdentifier: updatedItem.sourceBundleIdentifier,
            textContent: updatedItem.textContent,
            textFilename: updatedItem.textFilename,
            imageFilename: updatedItem.imageFilename,
            ocrText: updatedItem.ocrText,
            isTruncated: updatedItem.isTruncated,
            originalSizeBytes: updatedItem.originalSizeBytes
        )
        updatedItems.insert(updatedItem, at: 0)
        items = updatedItems

        scheduleHistorySave(updatedItems)
    }

    func clear() {
        storage.queueFileDeletions(items)
        items.removeAll()
        storage.clearCachedFullText()
        storage.clearCachedSearchText()

        scheduleHistorySave([])
    }

    var hasImagesOrLargeText: Bool {
        items.contains(where: storage.isImageOrLargeText)
    }

    func deleteImagesAndLargeText() {
        let removed = items.filter(storage.isImageOrLargeText)
        guard !removed.isEmpty else { return }

        let removedIDs = Set(removed.map(\.id))
        items.removeAll { removedIDs.contains($0.id) }

        for item in removed {
            storage.invalidateCachedFullText(for: item.id)
            storage.invalidateCachedSearchText(for: item.id)
            storage.queueFileDeletions([item])
        }

        scheduleHistorySave(items)
    }

    func combinedTextRepresentationForExport() async -> String {
        var exportedItems: [String] = []

        for item in items {
            switch item.type {
            case .text:
                if let text = await storage.cachedPreviewText(for: item), !text.isEmpty {
                    exportedItems.append(text)
                }
            case .image:
                exportedItems.append("Image")
            }
        }

        return exportedItems.joined(separator: "\n\n")
    }

    func combinedJSONRepresentationForExport() async -> String? {
        var exportItems: [ClipboardExportItem] = []

        for item in items {
            exportItems.append(
                ClipboardExportItem(
                    id: item.id,
                    type: item.type,
                    timestamp: item.timestamp,
                    sourceApp: item.sourceApp,
                    sourceBundleIdentifier: item.sourceBundleIdentifier,
                    textContent: item.type == .text ? await storage.cachedPreviewText(for: item) : nil,
                    imageFilename: item.imageFilename,
                    ocrText: item.ocrText,
                    isTruncated: item.isTruncated,
                    originalSizeBytes: item.originalSizeBytes
                )
            )
        }

        let snapshot = exportItems
        return await Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return nil as String? }
            return String(data: data, encoding: .utf8)
        }.value
    }

    func applyHistoryRetention(persist: Bool = true) {
        let retentionResult = applyingHistoryRetention(to: items)
        guard retentionResult.removed.isEmpty == false else { return }

        storage.queueFileDeletions(retentionResult.removed)
        retentionResult.removed.forEach { storage.invalidateCachedFullText(for: $0.id) }
        retentionResult.removed.forEach { storage.invalidateCachedSearchText(for: $0.id) }
        items = retentionResult.retained

        guard persist else { return }
        scheduleHistorySave(retentionResult.retained)
    }

    private func applyingHistoryRetention(to items: [ClipboardItem], referenceDate: Date = Date()) -> (retained: [ClipboardItem], removed: [ClipboardItem]) {
        let cutoffDate = historyLimit.cutoffDate(relativeTo: referenceDate, calendar: .autoupdatingCurrent)
        var retained: [ClipboardItem] = []
        var removed: [ClipboardItem] = []
        retained.reserveCapacity(items.count)
        for item in items {
            if item.timestamp >= cutoffDate {
                retained.append(item)
            } else {
                removed.append(item)
            }
        }
        return (retained, removed)
    }
}
