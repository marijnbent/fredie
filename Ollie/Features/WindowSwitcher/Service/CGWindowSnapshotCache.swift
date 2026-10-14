import Foundation
import CoreGraphics

@MainActor
final class CGWindowSnapshotCache {
    private struct Read {
        let revision: UInt64
        let task: Task<[CGWindowEntry], Never>
    }

    private let read: @Sendable () async -> [CGWindowEntry]
    private var revision: UInt64 = 0
    private var cachedRevision: UInt64?
    private var entries: [CGWindowEntry] = []
    private var pending: Read?
    private var generation = UUID()

    init(read: @escaping @Sendable () async -> [CGWindowEntry]) {
        self.read = read
    }

    func invalidate() {
        revision += 1
    }

    func snapshot() async -> [CGWindowEntry] {
        let requiredRevision = revision
        let generation = generation
        while !Task.isCancelled, generation == self.generation {
            if let cachedRevision, cachedRevision >= requiredRevision {
                return entries
            }
            let current: Read
            if let pending {
                current = pending
            } else {
                current = Read(revision: revision, task: Task { await read() })
                pending = current
            }
            let result = await current.task.value
            if pending?.revision == current.revision {
                entries = result
                cachedRevision = current.revision
                pending = nil
            }
        }
        return generation == self.generation ? entries : []
    }

    func reset() {
        generation = UUID()
        invalidate()
        pending?.task.cancel()
        pending = nil
        cachedRevision = nil
        entries = []
    }
}

struct CGWindowSnapshotReader: Sendable {
    func read() async -> [CGWindowEntry] {
        await Task.detached(priority: .utility) { Self.snapshot() }.value
    }

    private static func snapshot() -> [CGWindowEntry] {
        guard let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else {
            return []
        }

        return raw.enumerated().compactMap { order, entry in
            guard
                let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

            return CGWindowEntry(
                order: order,
                pid: ownerPID,
                title: entry[kCGWindowName as String] as? String,
                bounds: bounds,
                layer: layer,
                isOnScreen: (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true
            )
        }
    }
}
