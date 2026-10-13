import Foundation
import Observation

@MainActor
@Observable
final class ClipboardSearchSession {
    private(set) var query = ""
    private(set) var items: [ClipboardItem] = []
    private(set) var isSearching = false
    @ObservationIgnored private var task: Task<Void, Never>?
    private var revision = 0

    func search(_ text: String, items: [ClipboardItem], storage: ClipboardStorage, onReady: @escaping @MainActor () -> Void = {}) {
        cancel()
        query = text
        self.items = []
        let normalized = ClipboardStorage.normalizeSearchText(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.hasPrefix(":"), !normalized.isEmpty else {
            self.items = text.hasPrefix(":") ? [] : Array(items.prefix(50))
            onReady()
            return
        }
        isSearching = true
        let current = revision
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                try? await Task.sleep(for: .milliseconds(70))
                guard !Task.isCancelled else { return nil as ClipboardSearchScan? }
                return storage.search(items, normalizedQuery: normalized)
            }
            let scan = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, !Task.isCancelled, current == revision, let scan else { return }
            self.items = scan.matches
            isSearching = false
            onReady()
        }
    }

    func reset() {
        cancel()
        query = ""
        items = []
    }

    func cancel() {
        task?.cancel()
        task = nil
        revision += 1
        isSearching = false
    }
}
