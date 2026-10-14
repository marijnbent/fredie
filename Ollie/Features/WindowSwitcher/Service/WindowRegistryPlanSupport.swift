import Foundation

enum WindowRegistryRefreshReason: Hashable, Sendable {
    case startup
    case appLaunched
    case appActivated
    case activeSpaceChanged
    case panelOpened
    case activationRequested
    case windowCreated
    case windowDestroyed
    case windowTitleChanged
    case windowFocusChanged
    case windowMovedOrResized
    case windowMinimizedStateChanged
    case retryAfterFailure
    case periodicReconciliation

    var benchmarkName: String {
        switch self {
        case .startup: "startup"
        case .appLaunched: "app_launched"
        case .appActivated: "app_activated"
        case .activeSpaceChanged: "active_space_changed"
        case .panelOpened: "panel_opened"
        case .activationRequested: "activation_requested"
        case .windowCreated: "window_created"
        case .windowDestroyed: "window_destroyed"
        case .windowTitleChanged: "window_title_changed"
        case .windowFocusChanged: "window_focus_changed"
        case .windowMovedOrResized: "window_moved_or_resized"
        case .windowMinimizedStateChanged: "window_minimized_state_changed"
        case .retryAfterFailure: "retry_after_failure"
        case .periodicReconciliation: "periodic_reconciliation"
        }
    }

    var startsFreshRetrySequence: Bool {
        switch self {
        case .retryAfterFailure, .periodicReconciliation, .activeSpaceChanged, .panelOpened:
            false
        default:
            true
        }
    }

    var usesCachedCGEntries: Bool {
        self == .windowTitleChanged
    }
}

struct WindowRegistryRefreshPolicy: Equatable {
    var launchGraceInterval: TimeInterval = 0.2
    var fastEventCoalescingInterval: TimeInterval = 0.05
    var moveResizeCoalescingInterval: TimeInterval = 0.2
    var titleCoalescingInterval: TimeInterval = 0.1
    var retryInterval: TimeInterval = 0.35
    var maximumRetryInterval: TimeInterval = 5
    var maximumAutomaticRetryCount = 5
    var periodicReconciliationInterval: TimeInterval = 30

    func coalescingInterval(for reason: WindowRegistryRefreshReason) -> TimeInterval {
        switch reason {
        case .startup, .activeSpaceChanged, .periodicReconciliation, .activationRequested:
            return 0
        case .appLaunched:
            return launchGraceInterval
        case .windowMovedOrResized:
            return moveResizeCoalescingInterval
        case .windowTitleChanged:
            return titleCoalescingInterval
        case .retryAfterFailure:
            return retryInterval
        case .appActivated, .panelOpened, .windowCreated, .windowDestroyed, .windowMinimizedStateChanged, .windowFocusChanged:
            return fastEventCoalescingInterval
        }
    }

    func retryInterval(afterFailureCount failureCount: Int) -> TimeInterval? {
        guard failureCount > 0, failureCount <= maximumAutomaticRetryCount else {
            return nil
        }

        let multiplier = pow(2, Double(failureCount - 1))
        return min(retryInterval * multiplier, maximumRetryInterval)
    }
}
