import AppKit
import Foundation

struct ClipboardTextChunkSource: Sendable {
    let fileURL: URL?
    let inlineText: String
    let originalSizeBytes: Int?
}

struct ClipboardExportItem: Encodable, Sendable {
    let id: UUID
    let type: ClipboardItemType
    let timestamp: Date
    let sourceApp: String?
    let sourceBundleIdentifier: String?
    let textContent: String?
    let imageFilename: String?
    let ocrText: String?
    let isTruncated: Bool
    let originalSizeBytes: Int?
}

struct ClipboardSearchMetrics: Sendable {
    var scannedItemCount = 0
    var inlineTextItemCount = 0
    var fileBackedItemCount = 0
    var imageItemCount = 0
    var fileFullTextChecks = 0
    var fileCacheHits = 0
    var fileCacheMisses = 0
    var fileBytesLoaded = 0
    var fileLoadMilliseconds = 0.0
    var normalizationMilliseconds = 0.0
    var slowestItemMilliseconds = 0.0
    var slowestItemBytes = 0
    var slowestItemKind = "none"
    var activeSearchCountAtStart = 0
    var scanMilliseconds = 0.0
}

struct ClipboardSearchScan: Sendable {
    let matches: [ClipboardItem]
    let metrics: ClipboardSearchMetrics
}

final class ClipboardStorage: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let saveStateLock = NSLock()
    private let searchStateLock = NSLock()
    private var latestReferencedFiles: Set<String> = []
    private var pendingFileDeletions: [UUID: ClipboardItem] = [:]
    private var activeSearchCount = 0
    let imageCache: ClipboardImageCache
    private let fullTextCache = NSCache<NSUUID, NSString>()
    private let fileTextSearchCache = NSCache<NSUUID, NSString>()
    let storageDirectory: URL
    private var historyFileURL: URL { storageDirectory.appendingPathComponent("history.json") }
    private var imagesDirectory: URL { storageDirectory.appendingPathComponent("images", isDirectory: true) }
    private var textsDirectory: URL { storageDirectory.appendingPathComponent("texts", isDirectory: true) }

    init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
        imageCache = ClipboardImageCache(imagesDirectory: storageDirectory.appendingPathComponent("images"))
        fullTextCache.totalCostLimit = 8 * 1_024 * 1_024
        fileTextSearchCache.totalCostLimit = 16 * 1_024 * 1_024
        ensureDirectoriesExist()
    }

    func readHistory() throws -> [ClipboardItem] {
        guard fileManager.fileExists(atPath: historyFileURL.path) else { return [] }
        let items = try JSONDecoder().decode([ClipboardItem].self, from: Data(contentsOf: historyFileURL))
        guard Set(items.map(\.id)).count == items.count else { throw ClipboardContentError.unavailable }
        for item in items {
            if let name = item.textFilename { _ = try Self.contentURL(name, in: textsDirectory) }
            if let name = item.imageFilename { _ = try Self.contentURL(name, in: imagesDirectory) }
        }
        return items
    }

    static func contentURL(_ filename: String, in directory: URL) throws -> URL {
        guard !filename.isEmpty, filename != ".", filename != "..",
              !filename.contains("/"), !filename.contains("\\") else { throw ClipboardContentError.unavailable }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let file = root.appendingPathComponent(filename).resolvingSymlinksInPath().standardizedFileURL
        guard file.deletingLastPathComponent() == root else { throw ClipboardContentError.unavailable }
        return file
    }

    func writeHistory(_ snapshot: [ClipboardItem]) throws {
        try JSONEncoder().encode(snapshot).write(to: historyFileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyFileURL.path)
        deleteUnreferencedFiles(afterSaving: snapshot)
    }

    func updateReferences(_ items: [ClipboardItem]) {
        saveStateLock.withLock { latestReferencedFiles = Self.referencedFiles(in: items) }
    }
    func loadActionText(for item: ClipboardItem) async throws -> String {
        try Task.checkCancellation()
        guard item.type == .text else { throw ClipboardContentError.unavailable }
        guard let filename = item.textFilename else {
            guard let text = item.textContent else { throw ClipboardContentError.unavailable }
            return text
        }
        if let cached = fullTextCache.object(forKey: item.id as NSUUID) {
            return cached as String
        }
        let work = Task.detached(priority: .userInitiated) { [self] in
            try Task.checkCancellation()
            let text = try loadFullTextFromDisk(filename: filename)
            try Task.checkCancellation()
            cacheFullText(text, for: item.id)
            return text
        }
        return try await withTaskCancellationHandler {
            let text = try await work.value
            try Task.checkCancellation()
            return text
        } onCancel: {
            work.cancel()
        }
    }

    func prepareClipboardContent(for item: ClipboardItem) async throws -> PreparedClipboardContent {
        if item.type == .text {
            return .text(try await loadActionText(for: item))
        }
        guard let filename = item.imageFilename else { throw ClipboardContentError.unavailable }
        let url = try Self.contentURL(filename, in: imagesDirectory)
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let png = try Data(contentsOf: url)
            try Task.checkCancellation()
            guard let bitmap = NSBitmapImageRep(data: png),
                  let tiff = bitmap.representation(using: .tiff, properties: [:]) else {
                throw ClipboardContentError.unavailable
            }
            try Task.checkCancellation()
            return PreparedClipboardContent.image(png: png, tiff: tiff)
        }
        return try await withTaskCancellationHandler {
            let content = try await work.value
            try Task.checkCancellation()
            return content
        } onCancel: {
            work.cancel()
        }
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard item.type == .image, let filename = item.imageFilename else { return nil }
        guard let url = try? Self.contentURL(filename, in: imagesDirectory) else { return nil }
        return NSImage(contentsOf: url)
    }

    func saveImage(_ data: Data) -> String? {
        let filename = UUID().uuidString + ".png"
        guard let url = try? Self.contentURL(filename, in: imagesDirectory) else { return nil }

        do {
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return filename
        } catch {
            print("[clippie] Failed to save image: \(error)")
            return nil
        }
    }

    func saveText(_ utf8Data: Data) -> String? {
        let filename = UUID().uuidString + ".txt"
        guard let url = try? Self.contentURL(filename, in: textsDirectory) else { return nil }

        do {
            try utf8Data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return filename
        } catch {
            print("[clippie] Failed to save text file: \(error)")
            return nil
        }
    }

    func cachedPreviewText(for item: ClipboardItem) async -> String? {
        guard item.type == .text else { return nil }
        return (try? await loadActionText(for: item)) ?? item.textContent
    }

    func search(_ items: [ClipboardItem], normalizedQuery: String) -> ClipboardSearchScan? {
        let collectDiagnostics = ClipboardDiagnostics().isEnabled
        let scanStart = collectDiagnostics ? ContinuousClock.now : nil
        var metrics = ClipboardSearchMetrics()
        if collectDiagnostics {
            metrics.activeSearchCountAtStart = beginSearch()
        }
        defer {
            if collectDiagnostics {
                endSearch()
            }
        }

        var matches: [ClipboardItem] = []
        matches.reserveCapacity(min(items.count, 50))
        var slowestItem: ClipboardItem?

        for item in items {
            guard !Task.isCancelled else { return nil }
            if collectDiagnostics {
                metrics.scannedItemCount += 1
                switch item.type {
                case .text where item.isFileBacked:
                    metrics.fileBackedItemCount += 1
                case .text:
                    metrics.inlineTextItemCount += 1
                case .image:
                    metrics.imageItemCount += 1
                }
            }

            let itemStart = collectDiagnostics ? ContinuousClock.now : nil
            if matchesSearch(
                item,
                normalizedQuery: normalizedQuery,
                metrics: &metrics,
                collectDiagnostics: collectDiagnostics
            ) {
                matches.append(item)
            }
            if let itemStart {
                let itemMilliseconds = ClipboardDiagnostics.elapsedMilliseconds(since: itemStart)
                if itemMilliseconds > metrics.slowestItemMilliseconds {
                    metrics.slowestItemMilliseconds = itemMilliseconds
                    slowestItem = item
                }
            }
        }

        if let slowestItem {
            metrics.slowestItemBytes = itemSize(for: slowestItem) ?? 0
            switch slowestItem.type {
            case .text where slowestItem.isFileBacked:
                metrics.slowestItemKind = "file_text"
            case .text:
                metrics.slowestItemKind = "inline_text"
            case .image:
                metrics.slowestItemKind = "image"
            }
        }
        if let scanStart {
            metrics.scanMilliseconds = ClipboardDiagnostics.elapsedMilliseconds(since: scanStart)
        }

        guard !Task.isCancelled else { return nil }
        return ClipboardSearchScan(matches: matches, metrics: metrics)
    }

    private func matchesSearch(
        _ item: ClipboardItem,
        normalizedQuery: String,
        metrics: inout ClipboardSearchMetrics,
        collectDiagnostics: Bool
    ) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }

        if item.type.rawValue.contains(normalizedQuery) {
            return true
        }

        if let sourceApp = item.sourceApp,
           Self.normalizedSearchText(
               sourceApp,
               metrics: &metrics,
               collectDiagnostics: collectDiagnostics
           ).contains(normalizedQuery) {
            return true
        }

        switch item.type {
        case .text:
            if let inlineText = item.textContent,
               Self.normalizedSearchText(
                   inlineText,
                   metrics: &metrics,
                   collectDiagnostics: collectDiagnostics
               ).contains(normalizedQuery) {
                return true
            }

            if item.isFileBacked,
               let fullText = normalizedFullTextForSearch(
                   for: item,
                   metrics: &metrics,
                   collectDiagnostics: collectDiagnostics
               ),
               fullText.contains(normalizedQuery) {
                return true
            }
        case .image:
            if let ocrText = item.ocrText,
               Self.normalizedSearchText(
                   ocrText,
                   metrics: &metrics,
                   collectDiagnostics: collectDiagnostics
               ).contains(normalizedQuery) {
                return true
            }
        }

        return false
    }

    static func normalizeSearchText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func normalizedSearchText(
        _ text: String,
        metrics: inout ClipboardSearchMetrics,
        collectDiagnostics: Bool
    ) -> String {
        guard collectDiagnostics else {
            return normalizeSearchText(text)
        }

        let start = ContinuousClock.now
        let normalizedText = normalizeSearchText(text)
        metrics.normalizationMilliseconds += ClipboardDiagnostics.elapsedMilliseconds(since: start)
        return normalizedText
    }

    func textChunkSource(for item: ClipboardItem) -> ClipboardTextChunkSource {
        if let filename = item.textFilename {
            return ClipboardTextChunkSource(
                fileURL: try? Self.contentURL(filename, in: textsDirectory),
                inlineText: "",
                originalSizeBytes: item.originalSizeBytes
            )
        } else {
            return ClipboardTextChunkSource(
                fileURL: nil,
                inlineText: item.textContent ?? "",
                originalSizeBytes: item.originalSizeBytes
            )
        }
    }

    static func readTextChunk(from source: ClipboardTextChunkSource, charCount: Int) -> (text: String, totalBytes: Int, reachedEOF: Bool)? {
        if let url = source.fileURL {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let totalBytes = attributes[.size] as? Int ?? 0

                let maximumBytesToRead = min(charCount * 4, totalBytes)

                let fileHandle = try FileHandle(forReadingFrom: url)
                defer { try? fileHandle.close() }

                let data = try fileHandle.read(upToCount: maximumBytesToRead) ?? Data()

                let fullChunkStr = String(decoding: data, as: UTF8.self)
                let exactChunkStr = String(fullChunkStr.prefix(charCount))

                let reachedEOF = fullChunkStr.count < charCount

                return (exactChunkStr, totalBytes, reachedEOF)

            } catch {
                print("[clippie] Failed to read text chunk: \(error)")
                return nil
            }
        } else {
            let content = source.inlineText
            let totalBytes = source.originalSizeBytes ?? content.utf8.count

            let prefix = String(content.prefix(charCount))
            let reachedEOF = content.count <= charCount

            return (prefix, totalBytes, reachedEOF)
        }
    }

    func itemSize(for item: ClipboardItem) -> Int? {
        if let original = item.originalSizeBytes {
            return original
        }

        switch item.type {
        case .text:
            if let filename = item.textFilename {
                guard let url = try? Self.contentURL(filename, in: textsDirectory) else { return nil }
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                return attributes?[.size] as? Int
            } else {
                return item.textContent?.utf8.count
            }
        case .image:
            if let filename = item.imageFilename {
                guard let url = try? Self.contentURL(filename, in: imagesDirectory) else { return nil }
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                return attributes?[.size] as? Int
            }
        }
        return nil
    }

    private func ensureDirectoriesExist() {
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: textsDirectory, withIntermediateDirectories: true)
    }

    func queueFileDeletions(_ items: [ClipboardItem]) {
        saveStateLock.withLock {
            for item in items {
                pendingFileDeletions[item.id] = item
            }
        }
    }

    private static func referencedFiles(in items: [ClipboardItem]) -> Set<String> {
        Set(items.flatMap { [$0.imageFilename, $0.textFilename].compactMap { $0 } })
    }

    private func deleteUnreferencedFiles(afterSaving savedItems: [ClipboardItem]) {
        let savedReferences = Self.referencedFiles(in: savedItems)
        let candidates = saveStateLock.withLock { Array(pendingFileDeletions.values) }
        for item in candidates {
            let files = [
                item.imageFilename.flatMap { try? Self.contentURL($0, in: imagesDirectory) },
                item.textFilename.flatMap { try? Self.contentURL($0, in: textsDirectory) }
            ].compactMap { $0 }
            var removed = true
            for url in files {
                let isReferenced = savedReferences.contains(url.lastPathComponent)
                    || saveStateLock.withLock { latestReferencedFiles.contains(url.lastPathComponent) }
                guard !isReferenced else {
                    removed = false
                    continue
                }
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    if fileManager.fileExists(atPath: url.path) {
                        removed = false
                    }
                }
            }
            if removed {
                _ = saveStateLock.withLock { pendingFileDeletions.removeValue(forKey: item.id) }
            }
        }
    }

    func isImageOrLargeText(_ item: ClipboardItem) -> Bool {
        item.type == .image || item.isFileBacked || item.isTruncated
    }

    private func normalizedFullTextForSearch(
        for item: ClipboardItem,
        metrics: inout ClipboardSearchMetrics,
        collectDiagnostics: Bool
    ) -> String? {
        guard let filename = item.textFilename else {
            return item.textContent.map {
                Self.normalizedSearchText(
                    $0,
                    metrics: &metrics,
                    collectDiagnostics: collectDiagnostics
                )
            }
        }

        if collectDiagnostics {
            metrics.fileFullTextChecks += 1
        }
        if let cached = cachedSearchText(for: item.id) {
            if collectDiagnostics {
                metrics.fileCacheHits += 1
            }
            return cached
        }

        if collectDiagnostics {
            metrics.fileCacheMisses += 1
        }
        do {
            let loadStart = collectDiagnostics ? ContinuousClock.now : nil
            let cachedText = fullTextCache.object(forKey: item.id as NSUUID).map { $0 as String }
            let text = try cachedText ?? loadFullTextFromDisk(filename: filename)
            if let loadStart, cachedText == nil {
                metrics.fileBytesLoaded += itemSize(for: item) ?? 0
                metrics.fileLoadMilliseconds += ClipboardDiagnostics.elapsedMilliseconds(since: loadStart)
            }
            guard !Task.isCancelled else { return nil }
            let normalizedText = Self.normalizedSearchText(
                text,
                metrics: &metrics,
                collectDiagnostics: collectDiagnostics
            )
            cacheSearchText(normalizedText, for: item.id)
            return normalizedText
        } catch {
            print("[clippie] Failed to load text for search: \(error)")
            return item.textContent.map(Self.normalizeSearchText)
        }
    }

    private func beginSearch() -> Int {
        searchStateLock.lock()
        defer { searchStateLock.unlock() }
        activeSearchCount += 1
        return activeSearchCount
    }

    private func endSearch() {
        searchStateLock.lock()
        activeSearchCount -= 1
        searchStateLock.unlock()
    }

    private func cachedSearchText(for id: UUID) -> String? {
        fileTextSearchCache.object(forKey: id as NSUUID).map { $0 as String }
    }

    private func loadFullTextFromDisk(filename: String) throws -> String {
        let url = try Self.contentURL(filename, in: textsDirectory)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func cacheFullText(_ text: String, for id: UUID) {
        fullTextCache.setObject(text as NSString, forKey: id as NSUUID, cost: text.utf8.count)
    }

    private func cacheSearchText(_ text: String, for id: UUID) {
        fileTextSearchCache.setObject(text as NSString, forKey: id as NSUUID, cost: text.utf8.count)
    }

    func invalidateCachedFullText(for id: UUID) {
        imageCache.invalidateThumbnail(for: id)
        fullTextCache.removeObject(forKey: id as NSUUID)
    }

    func invalidateCachedSearchText(for id: UUID) {
        fileTextSearchCache.removeObject(forKey: id as NSUUID)
    }

    func clearCachedFullText() {
        imageCache.removeAllThumbnails()
        fullTextCache.removeAllObjects()
    }

    func clearCachedSearchText() {
        fileTextSearchCache.removeAllObjects()
    }
}
