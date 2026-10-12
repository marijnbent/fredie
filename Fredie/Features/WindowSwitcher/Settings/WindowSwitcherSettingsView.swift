import SwiftUI

struct WindowSwitcherSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WindowSwitcherCoordinator.self) private var switcher

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Window Switcher", isOn: $settings.windowSwitcherEnabled)
                LegacyAppNotice(app: .windowSwitcher)
                if let conflict = switcher.conflict {
                    Text("Shortcut already used by \(conflict)").foregroundStyle(.orange)
                }
                if settings.windowSwitcherEnabled, !switcher.isRunning,
                   !switcher.isCapturingShortcut {
                    Button("Grant Accessibility and Input Monitoring…") { switcher.requestAccess() }
                }
            }
            Section("Shortcuts") {
                Toggle("⌘ Tab — all apps", isOn: $settings.switcherCommandTab)
                Toggle("⌘ ` — current app", isOn: $settings.switcherCommandBacktick)
                LabeledContent("Previous window", value: "⇧ ⌘ `")
            }
            Section {
                Picker("Windows", selection: $settings.switcherWindowSource) {
                    ForEach(WindowSource.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                visibility("Minimized windows", selection: $settings.switcherMinimizedMode)
                visibility("Hidden apps", selection: $settings.switcherHiddenMode)
                visibility("Apps without windows", selection: $settings.switcherAppsWithoutWindowsMode)
                Toggle("Preview windows while switching", isOn: $settings.switcherImmediatePreview)
            }
            Section {
                Toggle("Diagnostic logging", isOn: $settings.switcherDiagnostics)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.windowSwitcher)
    }

    private func visibility(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(VisibilityMode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
        }
    }
}
