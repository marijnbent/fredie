import Foundation
import ImageCaptureCore

typealias ScanProgress = @Sendable (Int, Int) async -> Void

final class ClipScanner: @unchecked Sendable {
    private let ffmpeg: FFmpegService

    init(ffmpeg: FFmpegService) {
        self.ffmpeg = ffmpeg
    }

    func scan(_ source: MediaSource, progress: @escaping ScanProgress = { _, _ in }) async throws -> [MediaClip] {
        guard ffmpeg.isAvailable else { throw ImportieError.ffmpegMissing }
        switch source.kind {
        case .folder(let url):
            let cameraRoots = MediaDiscovery.cameraMediaRoots(on: url)
            let roots = cameraRoots.isEmpty ? [url] : cameraRoots
            return try await scanFiles(MediaDiscovery.videoFiles(in: roots), progress: progress)
        case .camera(let cameraSource):
            return await scanCameraFiles(cameraSource.files)
        }
    }

    private func scanFiles(_ urls: [URL], progress: @escaping ScanProgress) async throws -> [MediaClip] {
        await progress(0, urls.count)
        let clips = await withTaskGroup(of: (Int, MediaClip).self) { group in
            var results = [MediaClip?](repeating: nil, count: urls.count)
            var nextIndex = 0
            var completed = 0
            for index in 0..<min(4, urls.count) {
                group.addTask { (index, await self.scanFile(urls[index])) }
                nextIndex += 1
            }
            for await (index, clip) in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                results[index] = clip
                completed += 1
                await progress(completed, urls.count)
                if nextIndex < urls.count {
                    let next = nextIndex
                    group.addTask { (next, await self.scanFile(urls[next])) }
                    nextIndex += 1
                }
            }
            return results.compactMap { $0 }
        }
        try Task.checkCancellation()
        return Self.mergingDualRecordings(in: clips)
            .sorted { $0.recordingDate < $1.recordingDate }
    }

    private func scanFile(_ url: URL) async -> MediaClip {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
        ])
        let probe = try? await ffmpeg.inspect(url)
        let date = probe?.creationDate
            ?? values?.creationDate
            ?? values?.contentModificationDate
            ?? Date()
        let size = Int64(values?.fileSize ?? 0)
        let modificationTime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fingerprint = "file|\(url.path)|\(size)|\(Int64(modificationTime))"
        return MediaClip(
            id: fingerprint,
            origin: .file(url),
            originalName: url.lastPathComponent,
            recordingDate: date,
            duration: probe?.duration ?? 0,
            fileSize: size,
            fingerprint: fingerprint,
            status: .ready
        )
    }

    static func mergingDualRecordings(in clips: [MediaClip]) -> [MediaClip] {
        var merged = clips
        var duplicateIDs = Set<String>()
        let mp4Indices = Dictionary(grouping: clips.indices.filter {
            clips[$0].isMP4File && clips[$0].duration > 0
        }) { floor(clips[$0].recordingDate.timeIntervalSince1970) }

        for mtsIndex in merged.indices where merged[mtsIndex].isAVCHDFile {
            let mts = merged[mtsIndex]
            guard mts.duration > 0 else { continue }
            let second = floor(mts.recordingDate.timeIntervalSince1970)
            var match: Int?
            var bestDifference: TimeInterval = 1
            for bucket in [second - 1, second, second + 1] {
                for index in mp4Indices[bucket] ?? [] {
                    let mp4 = merged[index]
                    guard !duplicateIDs.contains(mp4.id),
                          abs(mp4.recordingDate.timeIntervalSince(mts.recordingDate)) < 1 else { continue }
                    let difference = abs(mp4.duration - mts.duration)
                    if difference < bestDifference
                        || (difference == bestDifference && index < (match ?? -1)) {
                        match = index
                        bestDifference = difference
                    }
                }
            }
            guard let match, case .file(let mp4URL) = merged[match].origin else { continue }
            merged[mtsIndex].companionOriginalURLs.append(mp4URL)
            duplicateIDs.insert(merged[match].id)
        }

        return merged.filter { !duplicateIDs.contains($0.id) }
    }

    private func scanCameraFiles(_ references: [CameraFileReference]) async -> [MediaClip] {
        var clips: [MediaClip] = []
        for reference in references {
            if Task.isCancelled { break }
            let file = reference.file
            let date = file.exifCreationDate
                ?? file.fileCreationDate
                ?? file.fileModificationDate
                ?? Date()
            let name = file.originalFilename ?? file.name ?? "Video"
            let fingerprint = file.fingerprint
                ?? "camera|\(reference.deviceID)|\(name)|\(file.fileSize)|\(Int64(date.timeIntervalSince1970))"
            clips.append(MediaClip(
                id: reference.id,
                origin: .camera(reference),
                originalName: name,
                recordingDate: date,
                duration: file.duration,
                fileSize: Int64(file.fileSize),
                fingerprint: fingerprint,
                status: .ready
            ))
        }
        return clips.sorted { $0.recordingDate < $1.recordingDate }
    }
}

private extension MediaClip {
    var fileExtension: String? {
        guard case .file(let url) = origin else { return nil }
        return url.pathExtension.lowercased()
    }

    var isAVCHDFile: Bool { fileExtension == "mts" || fileExtension == "m2ts" }
    var isMP4File: Bool { fileExtension == "mp4" }
}
