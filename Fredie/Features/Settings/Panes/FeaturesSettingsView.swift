import SwiftUI

extension OllieFeature {
    @MainActor var enabledKeyPath: ReferenceWritableKeyPath<AppSettings, Bool> {
        switch self {
        case .launcher: \.launcherEnabled
        case .clipboard: \.clipboardEnabled
        case .snippets: \.snippetsEnabled
        case .dictation: \.dictationEnabled
        case .windowSwitcher: \.windowSwitcherEnabled
        case .ai: \.aiEnabled
        case .typingSounds: \.typingSoundsEnabled
        case .network: \.networkEnabled
        case .notifications: \.notificationsEnabled
        case .mediaImport: \.mediaImportEnabled
        }
    }
}

extension AppSettings {
    var enabledSettingsTabs: [SettingsTab] {
        SettingsTab.visible(for: Set(OllieFeature.allCases.filter { self[keyPath: $0.enabledKeyPath] }))
    }
}

struct FeaturesSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(OllieFeature.allCases) { feature in
                    Toggle(
                        isOn: Binding(
                            get: { settings[keyPath: feature.enabledKeyPath] },
                            set: { settings[keyPath: feature.enabledKeyPath] = $0 })
                    ) {
                        Label(feature.title, systemImage: feature.settingsTab.systemImage)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.features)
    }
}
