import AppKit
import ApplicationServices

enum WindowSource: String, Codable, CaseIterable {
    case allSpaces
    case visibleAndFullScreenSpaces
    case visibleSpaces

    var title: String {
        switch self {
        case .allSpaces:
            return "All Spaces"
        case .visibleAndFullScreenSpaces:
            return "Visible and Full Screen Spaces"
        case .visibleSpaces:
            return "Visible Spaces"
        }
    }
}

enum WindowScope {
    case allApps
    case activeApp
}

enum VisibilityMode: String, Codable, CaseIterable {
    case show
    case showAtBottom
    case doNotShow

    var title: String {
        switch self {
        case .show:
            return "Show"
        case .showAtBottom:
            return "Show at bottom"
        case .doNotShow:
            return "Do not show"
        }
    }
}

struct SwitcherSettings: Codable {
    var activationShortcuts: [SwitcherShortcut] = .defaultActivators
    var reverseShortcut: SwitcherShortcut = .reverseCommandBacktick
    var windowSource: WindowSource = .allSpaces
    var minimizedMode: VisibilityMode = .doNotShow
    var hiddenMode: VisibilityMode = .doNotShow
    var appsWithoutWindowsMode: VisibilityMode = .showAtBottom
    var switchWindowsImmediately = false
    var diagnosticsEnabled = false

    init(
        activationShortcuts: [SwitcherShortcut] = .defaultActivators,
        reverseShortcut: SwitcherShortcut = .reverseCommandBacktick,
        windowSource: WindowSource = .allSpaces,
        minimizedMode: VisibilityMode = .doNotShow,
        hiddenMode: VisibilityMode = .doNotShow,
        appsWithoutWindowsMode: VisibilityMode = .showAtBottom,
        switchWindowsImmediately: Bool = false,
        diagnosticsEnabled: Bool = false
    ) {
        self.activationShortcuts = activationShortcuts
        self.reverseShortcut = reverseShortcut
        self.windowSource = windowSource
        self.minimizedMode = minimizedMode
        self.hiddenMode = hiddenMode
        self.appsWithoutWindowsMode = appsWithoutWindowsMode
        self.switchWindowsImmediately = switchWindowsImmediately
        self.diagnosticsEnabled = diagnosticsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activationShortcuts = try container.decodeIfPresent([SwitcherShortcut].self, forKey: .activationShortcuts) ?? .defaultActivators
        reverseShortcut = try container.decodeIfPresent(SwitcherShortcut.self, forKey: .reverseShortcut) ?? .reverseCommandBacktick
        windowSource = try container.decodeIfPresent(WindowSource.self, forKey: .windowSource) ?? .allSpaces
        minimizedMode = try container.decodeIfPresent(VisibilityMode.self, forKey: .minimizedMode) ?? .doNotShow
        hiddenMode = try container.decodeIfPresent(VisibilityMode.self, forKey: .hiddenMode) ?? .doNotShow
        appsWithoutWindowsMode = try container.decodeIfPresent(VisibilityMode.self, forKey: .appsWithoutWindowsMode) ?? .showAtBottom
        switchWindowsImmediately = try container.decodeIfPresent(Bool.self, forKey: .switchWindowsImmediately) ?? false
        diagnosticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagnosticsEnabled) ?? false
    }
}

enum SwitcherItemKind: Equatable {
    case appOnly
    case window
}

enum SwitcherSelectionAction: Equatable {
    case activate
    case closeWindow
    case quitApp
}

struct SwitcherItem {
    let kind: SwitcherItemKind
    let appName: String
    let windowTitle: String?
    let displayTitle: String
    let appIcon: NSImage?
    let runningApplication: NSRunningApplication
    let windowElement: AXUIElement?
    let windowFrame: CGRect?
    let displayID: CGDirectDisplayID?
    let isHidden: Bool
    let isMinimized: Bool

    var axWindow: AXWindow? {
        guard let windowElement else { return nil }
        return AXWindow(
            element: windowElement, title: windowTitle, frame: windowFrame,
            isMinimized: isMinimized, isMain: false, isFocused: false
        )
    }

    func hasSameIdentity(as other: SwitcherItem) -> Bool {
        guard kind == other.kind,
              runningApplication.processIdentifier == other.runningApplication.processIdentifier else {
            return false
        }
        if kind == .appOnly {
            return true
        }
        guard let windowElement, let otherElement = other.windowElement else {
            return false
        }
        return CFEqual(windowElement, otherElement)
    }
}
