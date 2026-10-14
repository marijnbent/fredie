import AppKit
import SwiftUI

/// Owns the check-yourself panel: one at a time, and the camera stops with it.
@MainActor
final class CameraPreviewController {
    private let session = CameraSession()
    private var panel: CameraPanel?
    private var continuation: CheckedContinuation<Bool, Never>?
    /// Held across the camera warm-up too, so a chord repeating into it cannot stack previews.
    private var presenting = false
    private var generation = 0

    /// The camera settles first: a panel over a starting session shows a black stage.
    func present(meeting: MeetingEvent, now: Date) async -> Bool {
        guard !presenting else { return false }
        presenting = true
        generation += 1
        let revision = generation
        defer { if revision == generation { presenting = false } }
        let feed = await session.start()
        guard !Task.isCancelled, revision == generation else { return false }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            show(meeting: meeting, now: now, feed: feed)
        }
    }

    func stop() {
        generation += 1
        presenting = false
        let pending = continuation
        continuation = nil
        panel?.onAction = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        session.stop()
        pending?.resume(returning: false)
    }

    private func show(meeting: MeetingEvent, now: Date, feed: CameraSession.Feed) {
        let view = CameraPreviewView(
            meeting: meeting, now: now, feed: feed,
            onJoin: { [weak self] in self?.finish(true) },
            onCancel: { [weak self] in self?.finish(false) })
        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)
        let panel = CameraPanel(content: hosting)
        panel.onAction = { [weak self] action in self?.finish(action == .primary) }
        self.panel = panel
        let revision = generation
        panel.centerOnCursorScreen()
        // Non-activating like the palette: key focus without pulling the user out of their app.
        panel.fadeIn(duration: Theme.Duration.enter) { [weak self] in
            guard let self, self.panel === panel, generation == revision else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }

    private func finish(_ taken: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        let closing = panel
        panel = nil
        closing?.onAction = nil
        continuation.resume(returning: taken)
        let revision = generation
        // The camera goes with the panel, not before it: tearing it down mid-fade blanks the feed.
        closing?.fadeOut(duration: Theme.Duration.exit) { [weak self] in
            // Unless a preview raised inside the fade already owns the camera.
            guard let self, !presenting, generation == revision else { return }
            session.stop()
        }
    }
}
