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

    func search(_ text: String, items: [ClipboardItem], storage: ClipboardStorage,
                onReady: @escaping @MainActor ([ClipboardItem]) -> Void = { _ in }) {
        cancel()
        let sameQuery = query == text
        query = text
        if sameQuery {
            let currentItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            self.items = self.items.compactMap { currentItems[$0.id] }
        } else { self.items = [] }
        let normalized = ClipboardStorage.normalizeSearchText(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.hasPrefix(">"), !normalized.isEmpty else {
            let previousItems = self.items
            self.items = text.hasPrefix(">") ? [] : Array(items.prefix(50))
            onReady(previousItems)
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
            let previousItems = self.items
            self.items = scan.matches
            isSearching = false
            onReady(previousItems)
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
