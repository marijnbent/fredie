import AppKit

@MainActor
final class DictationWindowCoordinator {
    private let sessionState: DictationSessionState
    private let overlay: DictationOverlayController
    private let openSettings: () -> Void
    var onCycleLanguage: (() -> Void)? {
        didSet { overlay.onCycleLanguage = onCycleLanguage }
    }

    init(settings: DictationSettingsStore, session: DictationSessionState, openSettings: @escaping () -> Void) {
        sessionState = session
        overlay = DictationOverlayController(sessionState: session, settingsStore: settings)
        self.openSettings = openSettings
    }

    func showSettings() { openSettings() }

    func showOverlay(label: String, appIcon: NSImage?) {
        sessionState.overlayLabel = label
        sessionState.overlayAppIcon = appIcon
        sessionState.overlayVisible = true
        overlay.show()
    }

    func hideOverlay() {
        sessionState.overlayVisible = false
        sessionState.overlayAppIcon = nil
        overlay.hide()
    }
}

@MainActor
enum DictationFormatters {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
