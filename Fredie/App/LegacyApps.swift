import AppKit
import Observation

enum LegacyApp: String, CaseIterable, Sendable {
    case clipboard = "nl.bentjes.clippie"
    case dictation = "nl.bentjes.talkie"
    case windowSwitcher = "nl.bentjes.tabbie"
    case typingSounds = "nl.bentjes.typie"
    case mediaImport = "nl.bentjes.importie"
    case notifications = "nl.bentjes.ntfy-notifier"
    case network = "nl.bentjes.nettie"

    var name: String {
        switch self {
        case .clipboard: "Clippie"
        case .dictation: "Talkie"
        case .windowSwitcher: "Tabbie"
        case .typingSounds: "Typie"
        case .mediaImport: "Importie"
        case .notifications: "Ntfy Notifier"
        case .network: "Nettie"
        }
    }
}

@MainActor
@Observable
final class LegacyApps: HealthCheckable {
    private(set) var running: Set<LegacyApp> = []
    @ObservationIgnored private var observers: [NotificationToken] = []
    private let ticker: HealthTicker

    init(ticker: HealthTicker) { self.ticker = ticker }

    func start() {
        refresh()
        ticker.subscribe(self)
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(NotificationToken(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }, center: center))
        }
    }

    func stop() {
        observers.removeAll()
        ticker.unsubscribe(self)
    }

    func healthCheck() { refresh() }

    func isRunning(_ app: LegacyApp) -> Bool { running.contains(app) }

    func requestQuit(_ app: LegacyApp) {
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: app.rawValue) {
            application.terminate()
        }
    }

    private func refresh() {
        let next = Set(NSWorkspace.shared.runningApplications.compactMap { application -> LegacyApp? in
            guard !application.isTerminated, let identifier = application.bundleIdentifier else { return nil }
            return LegacyApp(rawValue: identifier)
        })
        if next != running { running = next }
    }
}
