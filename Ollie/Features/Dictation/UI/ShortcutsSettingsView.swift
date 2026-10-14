import SwiftUI

struct ShortcutsSettingsView: View {
    @Bindable var viewModel: DictationShortcutsController

    var body: some View {
        Section {
            if viewModel.shortcuts.isEmpty {
                Text("No shortcuts configured").foregroundStyle(.secondary)
            }
            ForEach(viewModel.shortcuts) { shortcut in
                if let shortcutBinding = viewModel.binding(forShortcutID: shortcut.id) {
                    let usedKeys = viewModel.usedKeys(excluding: shortcut.id)
                    HStack(spacing: Theme.Spacing.xl) {
                        Picker("Key", selection: shortcutBinding.key) {
                            ForEach(ShortcutKey.allCases.filter { $0 == shortcut.key || !usedKeys.contains($0) }) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                        Picker("Mode", selection: shortcutBinding.mode) {
                            ForEach(ShortcutMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        SettingsRemoveButton(label: "Remove shortcut") { viewModel.removeShortcut(id: shortcut.id) }
                            .disabled(viewModel.shortcuts.count <= 1)
                    }
                }
            }
            Button("Add Shortcut") { viewModel.addShortcut() }
                .disabled(!viewModel.canAddShortcut)
        } header: {
            Text("Shortcuts")
        } footer: {
            Text("Hold to record, click to toggle, or choose Both to use either gesture.")
        }
    }
}
