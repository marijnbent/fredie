import Foundation
import ApplicationServices

struct WindowRefreshRequest: @unchecked Sendable {
    var reasons: Set<WindowRegistryRefreshReason>
    var requiresCGRefresh: Bool
    private(set) var windowElements: [AXUIElement]?

    init(reason: WindowRegistryRefreshReason, element: AXUIElement? = nil, requiresCGRefresh: Bool? = nil) {
        reasons = [reason]
        self.requiresCGRefresh = requiresCGRefresh ?? !reason.usesCachedCGEntries
        switch reason {
        case .windowTitleChanged, .windowMovedOrResized, .windowMinimizedStateChanged:
            windowElements = element.map { [$0] }
        case .windowFocusChanged:
            windowElements = []
        default:
            windowElements = nil
        }
    }

    var startsFreshRetrySequence: Bool {
        reasons.contains { $0.startsFreshRetrySequence }
    }

    var updatesFocus: Bool {
        reasons.contains(.windowFocusChanged) || reasons.contains(.windowMinimizedStateChanged)
    }

    var benchmarkName: String {
        reasons.map(\.benchmarkName).sorted().joined(separator: "+")
    }

    mutating func merge(_ other: WindowRefreshRequest) {
        reasons.formUnion(other.reasons)
        requiresCGRefresh = requiresCGRefresh || other.requiresCGRefresh
        if let otherElements = other.windowElements, windowElements != nil {
            for element in otherElements {
                windowElements?.appendIfMissing(element)
            }
        } else {
            windowElements = nil
        }
    }
}

@MainActor
final class WindowRefreshScheduler {
    private struct Pending {
        var request: WindowRefreshRequest
        var waiters: [CheckedContinuation<Void, Never>]
    }

    private final class Entry {
        var pending: Pending?
        var task: Task<Void, Never>?
        var isRunning = false
        var deadline: ContinuousClock.Instant?
    }

    private var entries: [pid_t: Entry] = [:]
    private let run: @MainActor (pid_t, WindowRefreshRequest) async -> Void

    init(run: @escaping @MainActor (pid_t, WindowRefreshRequest) async -> Void) {
        self.run = run
    }

    func schedule(pid: pid_t, request: WindowRefreshRequest, delay: TimeInterval) {
        enqueue(pid: pid, request: request, delay: delay, waiter: nil)
    }

    func refresh(pid: pid_t, request: WindowRefreshRequest) async {
        await withCheckedContinuation { waiter in
            enqueue(pid: pid, request: request, delay: 0, waiter: waiter)
        }
    }

    func cancel(pid: pid_t) {
        guard let entry = entries[pid] else { return }
        entry.pending?.waiters.forEach { $0.resume() }
        entry.pending = nil
        entry.deadline = nil
        if !entry.isRunning {
            entry.task?.cancel()
            entries[pid] = nil
        }
    }

    func cancelAll() {
        for pid in Array(entries.keys) { cancel(pid: pid) }
    }

    private func enqueue(
        pid: pid_t,
        request: WindowRefreshRequest,
        delay: TimeInterval,
        waiter: CheckedContinuation<Void, Never>?
    ) {
        let entry = entries[pid] ?? Entry()
        entries[pid] = entry
        if entry.pending == nil {
            entry.pending = Pending(request: request, waiters: [])
        } else {
            entry.pending?.request.merge(request)
        }
        if let waiter { entry.pending?.waiters.append(waiter) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(delay))
        let movesEarlier = entry.deadline.map { deadline < $0 } ?? true
        if movesEarlier { entry.deadline = deadline }
        guard !entry.isRunning, entry.task == nil || movesEarlier else { return }
        entry.task?.cancel()
        entry.task = Task { [weak self] in
            guard let self else { return }
            while let deadline = entry.deadline {
                do { try await Task.sleep(until: deadline, clock: .continuous) }
                catch { return }
                guard entries[pid] === entry, let pending = entry.pending else { return }
                entry.isRunning = true
                entry.deadline = nil
                entry.pending = nil
                await run(pid, pending.request)
                pending.waiters.forEach { $0.resume() }
                entry.isRunning = false
            }
            entries[pid] = nil
        }
    }
}
