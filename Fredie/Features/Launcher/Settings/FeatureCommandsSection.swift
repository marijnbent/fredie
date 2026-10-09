import SwiftUI

struct FeatureCommandsSection: View {
    let owner: SettingsTab
    let anchor: SettingsAnchor
    /// Commands the pane draws elsewhere; excluded here rather than listed there, so a command
    /// added to `ownedCommands` later still shows up without a second edit.
    var excluding: Set<CommandID> = []

    var body: some View {
        Section {
            ForEach(CommandCatalog.entries(ownedBy: owner)) { entry in
                if !excluding.contains(where: { $0.rawValue == entry.id }) {
                    FeatureCommandRow(entry: entry)
                }
            }
        } header: {
            SettingsSectionHeader(anchor)
        }
    }
}

struct FeatureCommandRow: View {
    let entry: AppEntry

    var body: some View {
        SettingsRow(title: entry.name) {
            AppIconView(app: entry)
                .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
        } trailing: {
            if let action = entry.hotKeyAction {
                ShortcutRecorder(action: action)
            }
        }
    }
}
