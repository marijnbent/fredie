import AppKit
import Observation

@MainActor
@Observable
final class SpacesCoordinator: HealthCheckable {
    private let settings: AppSettings
    @ObservationIgnored private let switcher: SpaceSwitcher
    @ObservationIgnored private let monitor: SpaceSwipeMonitor
    @ObservationIgnored private let ticker: HealthTicker
    private(set) var isRunning = false
    private(set) var hasAccessibility = false

    init(settings: AppSettings, switcher: SpaceSwitcher, ticker: HealthTicker) {
        self.settings = settings
        self.switcher = switcher
        self.monitor = SpaceSwipeMonitor(switcher: switcher)
        self.ticker = ticker
    }

    func apply() {
        guard settings.spacesEnabled else {
            stop()
            return
        }
        ticker.subscribe(self)
        switcher.speed = SpaceTransitionSpeed(rawValue: settings.spacesTransitionSpeed) ?? .instant
        hasAccessibility = Permissions.isAccessibilityTrusted()
        guard hasAccessibility else {
            monitor.stop()
            switcher.stop()
            isRunning = false
            return
        }
        if !monitor.isRunning {
            monitor.stop()
            monitor.start()
        }
        isRunning = monitor.isRunning
    }

    func healthCheck() {
        guard settings.spacesEnabled else { return }
        if !monitor.isRunning || hasAccessibility != Permissions.isAccessibilityTrusted() { apply() }
    }

    func stop() {
        ticker.unsubscribe(self)
        monitor.stop()
        switcher.stop()
        switcher.speed = .instant
        isRunning = false
    }

    func requestAccess() {
        Permissions.ensureAccessibility()
        Permissions.openAccessibilitySettings()
        apply()
    }
}
