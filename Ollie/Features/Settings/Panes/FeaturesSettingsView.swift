import SwiftUI


extension AppSettings {
    var enabledSettingsTabs: [SettingsTab] {
        SettingsTab.visible(for: featureAvailability.enabledFeatures)
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
