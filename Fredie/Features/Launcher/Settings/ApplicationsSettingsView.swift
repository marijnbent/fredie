import SwiftUI

struct ApplicationsSettingsView: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Launcher", isOn: $settings.launcherEnabled)
            }
            LauncherCategorySwitchSection(
                kind: .application, anchor: .applicationsApplications)

            SearchScopesSection()

            LauncherItemsSection(
                kind: .application,
                anchor: .applicationsApplications,
                searchPrompt: "Search applications…")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.applications)
        .releasesFocusOnOutsideClick()
    }

}
