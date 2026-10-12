import SwiftUI

/// A SwiftUI split, not `NSSplitViewController`: only its sidebar gives `.searchable` a soft edge.
struct SettingsRootView: View {
    @Environment(SettingsNavigationState.self) private var navigation
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView()
                // Ahead of the width: applied after it, the column shrinks to AppKit's default.
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(
                    min: Theme.Size.settingsSidebar, ideal: Theme.Size.settingsSidebar,
                    max: Theme.Size.settingsSidebar)
        } detail: {
            SettingsDetailView()
                .frame(minWidth: Theme.Size.settingsDetailMinimum)
        }
        .onChange(of: settings.enabledSettingsTabs, initial: true) { _, tabs in
            navigation.updateAvailable(Set(tabs))
        }
        .navigationTitle(navigation.tab.title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button("Back", systemImage: "chevron.backward") { navigation.goBack() }
                        .disabled(!navigation.canGoBack)
                    Button("Forward", systemImage: "chevron.forward") { navigation.goForward() }
                        .disabled(!navigation.canGoForward)
                }
                .controlGroupStyle(.navigation)
            }
        }
    }
}
