import Foundation

@MainActor
final class WindowReconciliationScheduler {
    private let run: (WindowRefreshRequest) async -> Void
    private var pending: WindowRefreshRequest?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var isInteracting = false

    init(run: @escaping (WindowRefreshRequest) async -> Void) {
        self.run = run
    }

    func setInteractionState(panelOpen: Bool, activationPending: Bool) {
        isInteracting = panelOpen || activationPending
        startIfNeeded()
    }

    func schedule(_ reason: WindowRegistryRefreshReason) {
        let request = WindowRefreshRequest(reason: reason, requiresCGRefresh: false)
        if pending == nil {
            pending = request
        } else {
            pending?.merge(request)
        }
        startIfNeeded()
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        pending = nil
        isInteracting = false
    }

    private var canRun: Bool {
        guard let pending else { return false }
        return !isInteracting || pending.reasons.contains(.startup)
    }

    private func startIfNeeded() {
        guard task == nil, canRun else { return }
        let generation = generation
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, canRun, let request = pending {
                pending = nil
                await run(request)
            }
            if self.generation == generation { task = nil }
        }
    }
}
