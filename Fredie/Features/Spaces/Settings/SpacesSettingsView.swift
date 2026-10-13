import SwiftUI

struct SpacesSettingsView: View {
    @Environment(SpacesCoordinator.self) private var spaces
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            if !spaces.hasAccessibility {
                Section { SettingsPermissionRow(title: "Accessibility") { spaces.requestAccess() } }
            } else if !spaces.isRunning {
                Section {
                    SettingsNotice("Couldn’t start swipe interception", isError: true)
                    Button("Retry") { spaces.apply() }
                }
            }
            Section {
                Picker("Transition", selection: $settings.spacesTransitionSpeed) {
                    ForEach(SpaceTransitionSpeed.allCases, id: \.rawValue) { speed in
                        Text(speed.title).tag(speed.rawValue)
                    }
                }
            }
            Section("Shortcuts") { SpacesShortcutRows() }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.spaces)
    }
}

struct SpacesShortcutRows: View {
    static let actions: [HotKeyAction] = [.windowCommand(id: .previousSpace), .windowCommand(id: .nextSpace)]

    var body: some View {
        SettingsRow(title: "Previous Space") { ShortcutRecorder(action: Self.actions[0]) }
        SettingsRow(title: "Next Space") { ShortcutRecorder(action: Self.actions[1]) }
    }
}
