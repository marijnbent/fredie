import AppKit
import SwiftUI

/// Owns the standalone camera surface: one panel at a time, and the camera stops with it.
@MainActor
@Observable
final class CameraCoordinator {
    private(set) var feed: CameraSession.Feed = .noCamera
    private(set) var canSwitchCamera = false
    /// Remembered for the launch, so reopening the command keeps the framing you were happy with.
    var mirrored = true

    @ObservationIgnored private let session = CameraSession(.capture)
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var panel: CameraPanel?
    /// Held across the camera warm-up too, so a chord repeating into it cannot stack panels.
    @ObservationIgnored private var opening = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var operation: Task<Void, Never>?

    init(core: AppCore) {
        self.core = core
    }

    /// The camera settles first: a panel over a starting session shows a black stage.
    func show() async {
        guard core.settings.launcherEnabled else { return }
        // A panel system UI left without key takes it back, so ↵ and Esc reach it again.
        if let panel {
            panel.makeKey()
            return
        }
        guard !opening else { return }
        opening = true
        generation += 1
        let revision = generation
        defer { if generation == revision { opening = false } }
        feed = await session.start()
        guard !Task.isCancelled, revision == generation, core.settings.launcherEnabled else { return }
        canSwitchCamera = session.hasMultipleDevices
        present()
    }

    func stop() {
        generation += 1
        opening = false
        operation?.cancel()
        operation = nil
        panel?.onAction = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        session.stop()
        feed = .noCamera
        canSwitchCamera = false
    }

    func close() {
        guard let closing = panel else { return }
        panel = nil
        closing.onAction = nil
        let revision = generation
        // The camera goes with the panel, not before it: tearing it down mid-fade blanks the feed.
        closing.fadeOut(duration: Theme.Duration.exit) { [weak self] in
            // Unless a panel raised inside the fade already owns the camera.
            guard let self, !opening, generation == revision else { return }
            session.stop()
        }
    }

    func switchCamera() {
        guard core.settings.launcherEnabled else { return }
        operation?.cancel()
        operation = Task { [weak self] in
            guard let self, !Task.isCancelled, core.settings.launcherEnabled else { return }
            await session.switchToNextDevice()
        }
    }

    /// The panel goes with the shot: the command is done, and the camera light goes out with it.
    func takePhoto() {
        guard core.settings.launcherEnabled, case .live = feed else { return }
        let mirrored = mirrored
        let revision = generation
        operation?.cancel()
        operation = Task { [weak self] in
            guard let self else { return }
            let png = await session.capturePhoto(mirrored: mirrored)
            guard !Task.isCancelled, generation == revision, core.settings.launcherEnabled else { return }
            close()
            guard let png else {
                core.showMessage("Couldn't take the photo", tone: .danger)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
            core.showMessage("Photo copied")
        }
    }

    private func present() {
        let hosting = NSHostingView(rootView: CameraView(coordinator: self))
        hosting.setFrameSize(hosting.fittingSize)
        let panel = CameraPanel(content: hosting)
        panel.onAction = { [weak self] action in
            guard let self else { return }
            if action == .primary { takePhoto() } else { close() }
        }
        self.panel = panel
        let revision = generation
        panel.centerOnCursorScreen()
        // Non-activating like the palette: key focus without pulling the user out of their app.
        panel.fadeIn(duration: Theme.Duration.enter) { [weak self] in
            guard let self, self.panel === panel, self.generation == revision,
                  core.settings.launcherEnabled else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }
}
