import Foundation

@MainActor
final class SwitcherActivation {
    var onChange: (() -> Void)?
    var onFailure: ((SwitcherItem) -> Void)?
    private(set) var pendingItem: SwitcherItem?
    private(set) var previewedItem: SwitcherItem?
    private var task: Task<Void, Never>?
    private var retryAfterConfirmation = false
    private var confirmationRequested = false

    var isPending: Bool { task != nil }

    func activate(
        _ item: SwitcherItem,
        confirming: Bool = false,
        operation: @escaping @MainActor (SwitcherItem) async throws(CancellationError) -> SwitcherItem?
    ) {
        if pendingItem?.hasSameIdentity(as: item) == true {
            if confirming {
                retryAfterConfirmation = true
                confirmationRequested = true
            }
            return
        }

        cancel()
        confirmationRequested = confirming
        pendingItem = item
        task = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            var activated: SwitcherItem?
            var interrupted = false
            do {
                activated = try await operation(item)
                guard !Task.isCancelled else { return }
                if activated == nil, retryAfterConfirmation {
                    activated = try await operation(item)
                }
            } catch {
                interrupted = true
            }
            guard !Task.isCancelled else { return }
            let reportFailure = confirmationRequested && activated == nil && !interrupted
            task = nil
            pendingItem = nil
            previewedItem = activated
            retryAfterConfirmation = false
            confirmationRequested = false
            onChange?()
            if reportFailure { onFailure?(item) }
        }
        onChange?()
    }

    func cancel() {
        task?.cancel()
        task = nil
        pendingItem = nil
        previewedItem = nil
        retryAfterConfirmation = false
        confirmationRequested = false
    }
}
