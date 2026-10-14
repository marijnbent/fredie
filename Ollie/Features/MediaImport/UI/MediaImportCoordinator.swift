import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
final class MediaImportCoordinator {
    let state: MediaImportState
    private let monitor = MediaSourceMonitor()
    private unowned let core: AppCore
    private var running = false
    private var deletion: Task<Void, Never>?
    private var transition: Task<Void, Never>?
    private var generation = 0
    private var sourcePanel: NSOpenPanel?
    @ObservationIgnored private lazy var window = AppWindowController(
        title: "Media Import", contentSize: CGSize(width: 900, height: 650),
        minimumSize: CGSize(width: 760, height: 520), resizable: true,
        autosaveName: "MediaImport", activation: core.activationPolicy)

    init(core: AppCore) {
        self.core = core
        state = MediaImportState(isEnabled: { [weak core] in
            core?.settings.allows(.feature(.mediaImport)) ?? false
        })
        state.onRequestWindow = { [weak self] in self?.show() }
        monitor.onSourceDetected = { [weak self] source in self?.state.handleDetectedSource(source) }
        monitor.onSourceRemoved = { [weak self] id in self?.state.handleRemovedSource(id: id) }
        monitor.onVolumesChanged = { [weak self] in self?.state.refreshDestinations() }
    }

    func apply() {
        guard core.settings.mediaImportEnabled else {
            stop()
            return
        }
        guard !running else { return }
        generation += 1
        let revision = generation
        transition?.cancel()
        transition = Task { [weak self] in
            guard let self else { return }
            await state.finishStopping()
            guard !Task.isCancelled, revision == generation, core.settings.mediaImportEnabled else { return }
            running = true
            monitor.start()
            transition = nil
        }
    }

    func stop() {
        generation += 1
        running = false
        transition?.cancel()
        transition = nil
        monitor.stop()
        state.stop()
        deletion?.cancel()
        deletion = nil
        sourcePanel?.cancel(nil)
        sourcePanel = nil
        window.close()
    }

    func show() {
        guard core.settings.mediaImportEnabled else {
            core.settingsCoordinator.showSettings(tab: .mediaImport)
            return
        }
        window.show {
            MediaImportView(state: state, settings: state.settingsStore,
                onChooseSource: { [weak self] in self?.chooseSource() },
                onOpenSettings: { [weak self] in self?.core.settingsCoordinator.showSettings(tab: .mediaImport) },
                onDeleteOriginals: { [weak self] in self?.confirmDeletion() },
                onError: { [weak self] message in
                    await self?.core.showNotice(title: "Media Import", message: message,
                        symbol: "exclamationmark.triangle", tone: .danger)
                })
        }
    }

    func reportError(_ message: String) { core.showMessage(message, tone: .danger) }

    func chooseSource() {
        guard core.settings.mediaImportEnabled, running, sourcePanel == nil else { return }
        let panel = NSOpenPanel()
        sourcePanel = panel
        let revision = generation
        defer { if sourcePanel === panel { sourcePanel = nil } }
        panel.title = "Choose Camera or Video Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, core.settings.mediaImportEnabled,
              running, revision == generation, let url = panel.url else { return }
        state.load(monitor.manualSource(for: url))
        show()
    }

    private func confirmDeletion() {
        guard core.settings.mediaImportEnabled, running, deletion == nil, state.prepareOriginalDeletion() else { return }
        let revision = generation
        let sourceID = state.source?.id
        let count = state.deletableOriginalCount
        deletion = Task { [weak self] in
            guard let self else { return }
            defer { deletion = nil }
            let confirmed = await core.confirm(title: "Delete Imported Originals?",
                message: "Permanently delete \(count) source files from \(state.source?.name ?? "the source")?",
                symbol: "trash", confirmTitle: "Delete Permanently")
            guard confirmed, !Task.isCancelled, core.settings.mediaImportEnabled,
                  running, revision == generation, state.source?.id == sourceID,
                  state.deletableOriginalCount == count else { return }
            state.deleteImportedOriginals()
        }
    }
}
