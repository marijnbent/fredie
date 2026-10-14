import SwiftUI

struct OllieShortcutsSettingsView: View {
    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(DictationCoordinator.self) private var dictation
    @Environment(WindowSwitcherCoordinator.self) private var switcher
    @Environment(SettingsNavigationState.self) private var navigation
    @Environment(AppSettings.self) private var settings

    private let primary: [HotKeyAction] = [
        .togglePalette, .command(.clipboardHistory), .command(.searchEmoji), .command(.aiChat)
    ]

    private func isEnabled(_ action: HotKeyAction) -> Bool {
        action.capability.map(settings.allows) ?? true
    }

    var body: some View {
        Form {
            Section {
                ForEach(primary.filter(isEnabled), id: \.self) { action in
                    SettingsRow(title: hotKeys.displayName(of: action)) { ShortcutRecorder(action: action) }
                }
            }
            if settings.dictationEnabled {
                Section("Dictation") {
                    ForEach(dictation.settings.shortcuts) { shortcut in
                        LabeledContent(shortcut.key.displayName, value: shortcut.mode.displayName)
                    }
                    if let conflict = dictation.conflict {
                        SettingsNotice("Already used by \(conflict)", isError: false)
                    }
                    Button("Edit Dictation Shortcuts…") { navigation.select(.dictation) }
                }
            }
            if settings.spacesEnabled {
                Section("Spaces") { SpacesShortcutRows() }
            }
            if settings.windowSwitcherEnabled {
                Section("Window Switcher") {
                    if settings.switcherCommandTab { LabeledContent("All apps", value: "⌘ Tab") }
                    if settings.switcherCommandBacktick { LabeledContent("Current app", value: "⌘ `") }
                    LabeledContent("Previous window", value: "⇧ ⌘ `")
                    if let conflict = switcher.conflict {
                        SettingsNotice("Already used by \(conflict)", isError: false)
                    }
                    Button("Edit Window Switcher…") { navigation.select(.windowSwitcher) }
                }
            }
            let other = hotKeys.assignedActions.filter {
                !primary.contains($0) && isEnabled($0)
                    && !(settings.spacesEnabled && SpacesShortcutRows.actions.contains($0))
            }
            if !other.isEmpty {
                Section("Other Shortcuts") {
                    ForEach(other, id: \.self) { action in
                        SettingsRow(title: hotKeys.displayName(of: action)) { ShortcutRecorder(action: action) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.shortcuts)
    }
}
