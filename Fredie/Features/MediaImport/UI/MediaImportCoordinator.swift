import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
final class MediaImportCoordinator {
    let state = MediaImportState()
    private let monitor = MediaSourceMonitor()
    private unowned let core: AppCore
    private var running = false
    private var deletion: Task<Void, Never>?
    @ObservationIgnored private lazy var window = AppWindowController(
        title: "Media Import", contentSize: CGSize(width: 900, height: 650),
        minimumSize: CGSize(width: 760, height: 520), resizable: true,
        autosaveName: "MediaImport", activation: core.activationPolicy)

    init(core: AppCore) {
        self.core = core
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
        running = true
        monitor.start()
    }

    func stop() {
        monitor.stop()
        state.stop()
        deletion?.cancel()
        deletion = nil
        running = false
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
        let panel = NSOpenPanel()
        panel.title = "Choose Camera or Video Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.load(monitor.manualSource(for: url))
        show()
    }

    private func confirmDeletion() {
        guard deletion == nil, state.prepareOriginalDeletion() else { return }
        let sourceID = state.source?.id
        let count = state.deletableOriginalCount
        deletion = Task { [weak self] in
            guard let self else { return }
            defer { deletion = nil }
            let confirmed = await core.confirm(title: "Delete Imported Originals?",
                message: "Permanently delete \(count) source files from \(state.source?.name ?? "the source")?",
                symbol: "trash", confirmTitle: "Delete Permanently")
            guard confirmed, !Task.isCancelled, state.source?.id == sourceID,
                  state.deletableOriginalCount == count else { return }
            state.deleteImportedOriginals()
        }
    }
}
