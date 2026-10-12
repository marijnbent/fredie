import Foundation
import ImageCaptureCore

enum DestinationPathBuilder {
    static func monthDirectory(for date: Date, in root: URL, calendar: Calendar = .current) -> URL {
        let year = String(format: "%04d", calendar.component(.year, from: date))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MM-MMMM"
        let month = formatter.string(from: date).lowercased()
        return root
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
    }

    static func filename(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d %02d%02d.mp4",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    static func availableURL(
        for clip: MediaClip,
        in root: URL,
        calendar: Calendar = .current,
        fileManager: FileManager = .default,
        reserved: Set<URL> = []
    ) -> URL {
        let directory = monthDirectory(for: clip.recordingDate, in: root, calendar: calendar)
        let base = filename(for: clip.recordingDate, calendar: calendar).dropLast(4)
        var candidate = directory.appendingPathComponent("\(base).mp4")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) || reserved.contains(candidate) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix).mp4")
            suffix += 1
        }
        return candidate
    }
}

struct OriginalDeletionResult {
    let deleted: [URL]
    let failed: [OriginalDeletionFailure]
}

struct OriginalDeletionFailure {
    let url: URL
    let message: String
}

enum OriginalFileDeleter {
    static func isWritableDirectory(
        _ directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let probe = directory.appendingPathComponent(
            ".importie-write-probe-\(UUID().uuidString)"
        )
        do {
            try Data().write(to: probe, options: .withoutOverwriting)
            try fileManager.removeItem(at: probe)
            return true
        } catch {
            try? fileManager.removeItem(at: probe)
            return false
        }
    }

    static func isInsideSource(_ file: URL, sourceRoot: URL) -> Bool {
        let root = sourceRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = file.resolvingSymlinksInPath().standardizedFileURL.path
        return candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    static func delete(
        _ files: [URL],
        from sourceRoot: URL,
        fileManager: FileManager = .default
    ) -> OriginalDeletionResult {
        var deleted: [URL] = []
        var failed: [OriginalDeletionFailure] = []

        for file in files {
            guard isInsideSource(file, sourceRoot: sourceRoot) else {
                failed.append(OriginalDeletionFailure(
                    url: file,
                    message: "Importie blocked a path outside the selected source."
                ))
                continue
            }
            do {
                if fileManager.fileExists(atPath: file.path) {
                    try fileManager.removeItem(at: file)
                }
                deleted.append(file)
            } catch {
                failed.append(OriginalDeletionFailure(
                    url: file,
                    message: error.localizedDescription
                ))
            }
        }
        return OriginalDeletionResult(deleted: deleted, failed: failed)
    }
}

final class ImportLedger {
    private struct Record: Codable {
        let destinationPath: String
        let importedAt: Date
    }

    private let fileURL: URL
    private var records: [String: Record]

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = AppPaths.applicationSupport().appendingPathComponent("MediaImport", isDirectory: true)
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            self.fileURL = support.appendingPathComponent("ImportLedger.json")
        }
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    func reload() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        records = try JSONDecoder().decode([String: Record].self, from: Data(contentsOf: fileURL))
    }

    func destination(for fingerprint: String) -> URL? {
        guard let path = records[fingerprint]?.destinationPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    func record(fingerprint: String, destination: URL) throws {
        records[fingerprint] = Record(destinationPath: destination.path, importedAt: Date())
        try save()
    }

    func remove(fingerprints: [String]) throws {
        fingerprints.forEach { records[$0] = nil }
        try save()
    }

    private func save() throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class CameraDownloader: @unchecked Sendable {
    func download(_ reference: CameraFileReference, to directory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = reference.file.originalFilename ?? reference.file.name ?? "camera-video"
        let outputURL = directory.appendingPathComponent(filename)
        let directoryKey = ICDownloadOption(rawValue: "ICDownloadsDirectoryURL")
        let filenameKey = ICDownloadOption(rawValue: "ICSaveAsFilename")
        let overwriteKey = ICDownloadOption(rawValue: "ICOverwrite")

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                _ = reference.file.requestDownload(options: [
                    directoryKey: directory,
                    filenameKey: filename,
                    overwriteKey: true,
                ]) { savedFilename, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        let savedURL = savedFilename.map { directory.appendingPathComponent($0) } ?? outputURL
                        continuation.resume(returning: savedURL)
                    }
                }
            }
        } onCancel: {
            reference.device.cancelDownload()
        }
    }
}
