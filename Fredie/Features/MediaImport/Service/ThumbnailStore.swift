import AppKit
import ImageCaptureCore

@MainActor
final class ThumbnailStore {
    private struct Request {
        let id: UUID
        let clip: MediaClip
        let continuation: CheckedContinuation<NSImage?, Never>
    }

    private let cache = NSCache<NSString, NSImage>()
    private let load: @Sendable (MediaOrigin) async throws -> Data?
    private var queued: [Request] = []
    private var active: [UUID: Task<Void, Never>] = [:]

    init(load: @escaping @Sendable (MediaOrigin) async throws -> Data?) {
        self.load = load
        cache.countLimit = 128
        cache.totalCostLimit = 32 * 1_024 * 1_024
    }

    convenience init(ffmpeg: FFmpegService) {
        self.init { origin in
            switch origin {
            case .file(let url):
                return try await ffmpeg.thumbnail(url)
            case .camera(let reference):
                return await CameraThumbnailRequest.load { completion in
                    reference.file.requestThumbnailData(options: nil) { data, _ in
                        completion(data)
                    }
                }
            }
        }
    }

    func image(for clip: MediaClip) async -> NSImage? {
        guard !Task.isCancelled else { return nil }
        if let image = cache.object(forKey: clip.fingerprint as NSString) { return image }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                queued.append(Request(id: id, clip: clip, continuation: continuation))
                startNext()
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    func cancelAll() {
        let pending = queued
        queued.removeAll()
        pending.forEach { $0.continuation.resume(returning: nil) }
        active.values.forEach { $0.cancel() }
    }

    private func cancel(_ id: UUID) {
        if let index = queued.firstIndex(where: { $0.id == id }) {
            queued.remove(at: index).continuation.resume(returning: nil)
        }
        active[id]?.cancel()
    }

    private func startNext() {
        while active.count < 2, !queued.isEmpty {
            let request = queued.removeFirst()
            active[request.id] = Task {
                let data = try? await load(request.clip.origin)
                let image = Task.isCancelled ? nil : data.flatMap(NSImage.init(data:))
                if let image {
                    let cost = Int(image.size.width * image.size.height * 4)
                    cache.setObject(image, forKey: request.clip.fingerprint as NSString, cost: cost)
                }
                active[request.id] = nil
                request.continuation.resume(returning: image)
                startNext()
            }
        }
    }
}

final class CameraThumbnailRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var isFinished = false

    static func load(
        start: @Sendable (@escaping @Sendable (Data?) -> Void) -> Void
    ) async -> Data? {
        let request = CameraThumbnailRequest()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard request.begin(continuation) else { return }
                start { request.finish($0) }
            }
        } onCancel: {
            request.finish(nil)
        }
    }

    private func begin(_ continuation: CheckedContinuation<Data?, Never>) -> Bool {
        lock.lock()
        if isFinished {
            lock.unlock()
            continuation.resume(returning: nil)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    private func finish(_ data: Data?) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: data)
    }
}
