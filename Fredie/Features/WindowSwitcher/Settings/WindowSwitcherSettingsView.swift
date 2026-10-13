import SwiftUI

struct WindowSwitcherSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WindowSwitcherCoordinator.self) private var switcher

    var body: some View {
        @Bindable var settings = settings
        Form {
            if switcher.conflict != nil || (!switcher.isRunning && !switcher.isCapturingShortcut) {
                Section {
                    if let conflict = switcher.conflict {
                        SettingsNotice("Shortcut already used by \(conflict)", isError: false)
                    }
                    if !switcher.isRunning, !switcher.isCapturingShortcut {
                        SettingsPermissionRow(title: "Window access", subtitle: "Accessibility and Input Monitoring") {
                            switcher.requestAccess()
                        }
                    }
                }
            }
            Section("Shortcuts") {
                Toggle(isOn: $settings.switcherCommandTab) { Text("All apps"); Text("⌘ Tab") }
                Toggle(isOn: $settings.switcherCommandBacktick) { Text("Current app"); Text("⌘ `") }
                LabeledContent("Previous window", value: "⇧ ⌘ `")
            }
            Section("Windows") {
                Picker("Show", selection: $settings.switcherWindowSource) {
                    ForEach(WindowSource.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                visibility("Minimized windows", selection: $settings.switcherMinimizedMode)
                visibility("Hidden apps", selection: $settings.switcherHiddenMode)
                visibility("Apps without windows", selection: $settings.switcherAppsWithoutWindowsMode)
                Toggle("Preview windows while switching", isOn: $settings.switcherImmediatePreview)
            }
            Section("Advanced") {
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
