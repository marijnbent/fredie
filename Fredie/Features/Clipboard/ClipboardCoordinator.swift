import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ClipboardCoordinator: HealthCheckable {
    let store: ClipboardStore
    let snippets = SnippetStore()
    let watcher: ClipboardWatcher
    private unowned let core: AppCore
    private let ticker: HealthTicker
    @ObservationIgnored private lazy var expansion = SnippetExpansionController(store: snippets)
    @ObservationIgnored private var window: HistoryWindowController?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    private(set) var snippetsRunning = false
    var isCapturingShortcut = false { didSet { applyExpansion() } }
    var isRecording = false { didSet { applyExpansion() } }

    init(core: AppCore, ticker: HealthTicker) {
        self.core = core
        self.ticker = ticker
        store = ClipboardStore(storageDirectory: AppPaths.applicationSupport().appendingPathComponent("Clipboard"))
        watcher = ClipboardWatcher(store: store)
    }

    func apply() {
        core.appIndex.setCommandsVisible([.clipboardHistory], core.settings.clipboardEnabled || core.settings.snippetsEnabled)
        store.historyLimit = ClipboardHistoryLimit(rawValue: core.settings.clipboardHistoryDays) ?? .defaultValue
        applyExpansion()
        guard core.settings.clipboardEnabled else {
            watcher.stopWatching()
            return
        }
        load { [weak self] in
            guard let self, core.settings.clipboardEnabled, store.isLoaded else { return }
            watcher.startWatching()
        }
    }

    private func load(after: @escaping @MainActor () -> Void) {
        if store.isLoaded { after(); return }
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            await store.load()
            loadTask = nil
            guard !Task.isCancelled else { return }
            if store.isLoaded { apply() }
            after()
        }
    }

    func show() {
        guard core.settings.clipboardEnabled || core.settings.snippetsEnabled else { return }
        if window?.window?.isVisible == true { window?.close(); return }
        if window == nil {
            window = HistoryWindowController(store: store, snippets: snippets) { [weak self] error in
                self?.core.showMessage(error, tone: .danger)
            }
        }
        window?.showWindow(nil)
        load(after: {})
    }

    private func applyExpansion() {
        guard core.settings.snippetsEnabled, !isCapturingShortcut, !isRecording else {
            expansion.stop()
            ticker.unsubscribe(self)
            snippetsRunning = false
            return
        }
        ticker.subscribe(self)
        if !expansion.isRunning { expansion.stop(); expansion.start() }
        snippetsRunning = expansion.isRunning
    }

    func healthCheck() { if !expansion.isRunning { applyExpansion() } }

    func stop() {
        watcher.stopWatching()
        expansion.stop()
        ticker.unsubscribe(self)
        snippetsRunning = false
        window?.close()
        loadTask?.cancel()
    }

    func prepareForTermination() async -> Bool {
        stop()
        await loadTask?.value
        await watcher.finishPendingProcessing()
        guard store.isLoaded else { return true }
        return await store.flush()
    }

    func clearHistory(largeFilesOnly: Bool = false) async {
        guard store.isLoaded else { return }
        let title = largeFilesOnly ? "Delete images and large text?" : "Clear clipboard history?"
        guard await core.confirm(title: title, message: nil, symbol: "trash", confirmTitle: "Delete") else { return }
        if largeFilesOnly { store.deleteImagesAndLargeText() } else { store.clear() }
    }

    func exportHistory() async {
        guard store.isLoaded else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Clipboard.json"
        panel.allowedContentTypes = [.json]
        guard await panel.begin() == .OK, let url = panel.url,
              let json = await store.combinedJSONRepresentationForExport() else { return }
        do {
            try await Task.detached(priority: .utility) {
                try Data(json.utf8).write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }.value
        } catch { core.showMessage("Could not export clipboard history", tone: .danger) }
    }

    func deleteSnippet(_ snippet: Snippet) async {
        guard await core.confirm(title: "Delete :\(snippet.trigger)?", message: nil, symbol: "trash", confirmTitle: "Delete") else { return }
        snippets.deleteSnippet(id: snippet.id)
    }
}
