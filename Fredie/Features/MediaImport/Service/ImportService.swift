import Foundation

final class ImportService: @unchecked Sendable {
    private let ffmpeg: FFmpegService
    private let cameraDownloader = CameraDownloader()
    private let fileManager: FileManager
    private let destinationLock = NSLock()
    private var reservedDestinations = Set<URL>()

    init(ffmpeg: FFmpegService, fileManager: FileManager = .default) {
        self.ffmpeg = ffmpeg
        self.fileManager = fileManager
    }

    func importClip(_ clip: MediaClip, to destinationRoot: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        guard fileManager.fileExists(atPath: destinationRoot.path),
              fileManager.isWritableFile(atPath: destinationRoot.path) else {
            throw ImportieError.destinationUnavailable
        }

        try checkCapacity(for: clip, at: destinationRoot)
        let finalURL = destinationLock.withLock {
            let url = DestinationPathBuilder.availableURL(for: clip, in: destinationRoot, fileManager: fileManager, reserved: reservedDestinations)
            reservedDestinations.insert(url)
            return url
        }
        defer { _ = destinationLock.withLock { reservedDestinations.remove(finalURL) } }
        let directory = finalURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let partialURL = directory.appendingPathComponent(".importie-\(UUID().uuidString).partial.mp4")
        var downloadedDirectory: URL?

        defer {
            try? fileManager.removeItem(at: partialURL)
            if let downloadedDirectory {
                try? fileManager.removeItem(at: downloadedDirectory)
            }
        }

        let sourceURL: URL
        switch clip.origin {
        case .file(let url):
            guard fileManager.fileExists(atPath: url.path) else {
                throw ImportieError.sourceUnavailable(clip.originalName)
            }
            sourceURL = url
        case .camera(let reference):
            let temporaryDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("Importie", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            downloadedDirectory = temporaryDirectory
            sourceURL = try await cameraDownloader.download(reference, to: temporaryDirectory)
        }

        try Task.checkCancellation()
        try await ffmpeg.convertToMP4(source: sourceURL, destination: partialURL, duration: clip.duration) { progress($0 * 0.95) }
        progress(0.95)
        try Task.checkCancellation()
        try await verify(partialURL, expectedDuration: clip.duration, originalName: clip.originalName)
        try Task.checkCancellation()
        try fileManager.moveItem(at: partialURL, to: finalURL)
        try? fileManager.setAttributes([
            .creationDate: clip.recordingDate,
            .modificationDate: clip.recordingDate,
        ], ofItemAtPath: finalURL.path)
        progress(1)
        return finalURL
    }

    private func verify(_ url: URL, expectedDuration: TimeInterval, originalName: String) async throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let probe = try await ffmpeg.inspect(url)
        guard size > 0, probe.duration > 0 else {
            throw ImportieError.invalidOutput(originalName)
        }
        if expectedDuration > 0 {
            let allowedDifference = max(2, expectedDuration * 0.03)
            guard abs(probe.duration - expectedDuration) <= allowedDifference else {
                throw ImportieError.invalidOutput(originalName)
            }
        }
    }

    private func checkCapacity(for clip: MediaClip, at destination: URL) throws {
        let values = try destination.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else { return }
        let required = max(clip.fileSize * 2, 512 * 1_024 * 1_024)
        if available < required {
            throw CocoaError(.fileWriteOutOfSpace)
        }
    }
}
