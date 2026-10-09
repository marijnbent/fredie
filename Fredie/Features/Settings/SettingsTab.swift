enum SettingsTab: CaseIterable, Identifiable {
    case general, applications, systemSettings, systemActions, commands, quicklinks, appleShortcuts,
        fallbacks, fileSearch, windowManagement, navigation, notes, calendar, emoji,
        ai, quickActions, extensions, permissions, backup, about
    static let available: [Self] = [.general, .applications, .ai, .permissions, .backup, .about]

    /// The case, never an index: a selectable `List` flattens section and row IDs together.
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .applications: return "Applications"
        case .systemSettings: return "System Settings"
        case .systemActions: return "System Actions"
        case .commands: return "Commands"
        case .quicklinks: return "Quicklinks"
        case .appleShortcuts: return "Apple Shortcuts"
        case .fallbacks: return "Fallbacks"
        case .ai: return "AI"
        case .quickActions: return "Quick Actions"
        case .fileSearch: return "File Search"
        case .notes: return "Notes"
        case .navigation: return "Navigation"
        case .windowManagement: return "Window Management"
        case .emoji: return "Emoji & Symbols"
        case .calendar: return "Calendar"
        case .extensions: return "Extensions"
        case .permissions: return "Permissions"
        case .backup: return "Backup"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .applications: return "square.grid.2x2"
        case .systemSettings: return "gearshape"
        case .systemActions: return "bolt"
        case .commands: return "terminal"
        case .quicklinks: return "link"
        case .appleShortcuts: return "square.2.layers.3d"
        case .fallbacks: return "arrow.turn.down.right"
        case .ai: return "sparkles"
        case .quickActions: return "wand.and.sparkles"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .notes: return "text.page"
        case .navigation: return "arrow.left.arrow.right"
        case .windowManagement: return "macwindow"
        case .emoji: return "face.smiling"
        case .calendar: return "calendar"
        case .extensions: return "puzzlepiece.extension"
        case .permissions: return "lock.shield"
        case .backup: return "arrow.up.arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

enum SettingsSection: CaseIterable, Identifiable {
    case app, advanced
    var id: Self { self }

    var title: String {
        switch self {
        case .app: "Fredie"
        case .advanced: "Advanced"
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .app: [.general, .applications, .ai]
        case .advanced: [.permissions, .backup, .about]
        }
    }
}
