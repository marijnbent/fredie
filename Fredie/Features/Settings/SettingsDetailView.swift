import SwiftUI

/// The pane column: whichever pane the history currently points at.
struct SettingsDetailView: View {
    @Environment(SettingsNavigationState.self) private var navigation

    @Environment(LegacyDataCoordinator.self) private var adoption

    var body: some View {
        // Not a `TabView`: `NSTabView` re-hosts on selection and breaks the recorder.
        Group {
            switch navigation.tab {
            case .shortcuts: OllieShortcutsSettingsView()
            case .dictation: DictationSettingsView()
            case .windowSwitcher: WindowSwitcherSettingsView()
            case .clipboard: ClipboardSettingsView()
            case .snippets: SnippetsSettingsView()
            case .mediaImport: MediaImportSettingsView()
            case .notifications: NotificationsSettingsView()
            case .network: NetworkSettingsView()
            case .typingSounds: TypingSoundsSettingsView()
            case .general: GeneralSettingsView()
            case .applications: ApplicationsSettingsView()
            case .emoji: EmojiSettingsView()
            case .ai: AISettingsView()
            case .permissions: PermissionsSettingsView()
            case .backup: BackupSettingsView()
            case .about: AboutView()
            default: EmptyView()
            }
        }
        .disabled(adoption.active != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // One host for every pane, above their scroll views so a callout is never clipped.
        .shortcutRecorderPopoverHost()
    }
}
