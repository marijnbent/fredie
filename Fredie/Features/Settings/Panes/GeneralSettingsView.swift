import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    private var launcherRanking: LauncherRankingStore { core.launcherRanking }
    @State private var confirmingRankingReset = false
    @State private var inputSources: [InputSourceSwitcher.Option] = []

    var body: some View {
        @Bindable var settings = settings
        return Form {
            if settings.launcherEnabled {
            Section {
                SettingsRow(title: "App Launcher", anchor: .generalGlobalShortcuts) {
                    ShortcutRecorder(action: .togglePalette)
                }
            } header: {
                SettingsSectionHeader(.generalGlobalShortcuts)
            }
            }

            Section {
                Toggle(isOn: $settings.launchAtLogin) {
                    SettingsRowTitle(.generalGeneral, "Launch at login")
                }
                Toggle(isOn: $settings.showInMenuBar) {
                    SettingsRowTitle(.generalGeneral, "Show in menu bar")
                    Text("Shortcuts still work when hidden.")
                }
                Toggle(isOn: $settings.automaticallyCheckForUpdates) {
                    SettingsRowTitle(.generalGeneral, "Automatically check for updates")
                    Text("Check for Updates remains available when off.")
                }
                Toggle(isOn: $settings.diagnosticsEnabled) {
                    SettingsRowTitle(.generalGeneral, "Diagnostics")
                }
                if settings.launcherEnabled {
                Picker(selection: $settings.popToRootTimeout) {
                    ForEach(PopToRootTimeout.allCases) { timeout in
                        Text(timeout.title).tag(timeout)
                    }
                } label: {
                    SettingsRowTitle(.generalGeneral, "Pop to Root Search")
                    Text("After the launcher closes.")
                }
                Picker(selection: $settings.escapeKeyBehavior) {
                    ForEach(EscapeKeyBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                } label: {
                    SettingsRowTitle(.generalGeneral, "Escape Key Behavior")
                    Text("When the search field is empty.")
                }
                // Empty only when TIS fails; one layout still lists, so the row stays put.
                if !inputSources.isEmpty {
                    Picker(selection: $settings.autoSwitchInputSourceID) {
                        Text("None").tag(nil as String?)
                        ForEach(inputSources) { source in
                            Text(source.title).tag(Optional(source.id))
                        }
                    } label: {
                        SettingsRowTitle(.generalGeneral, "Auto-switch input source")
                        Text("While the launcher is open.")
                    }
                }
                }
            } header: {
                SettingsSectionHeader(.generalGeneral)
            }

            Section {
                Picker(selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                } label: {
                    SettingsRowTitle(.generalAppearance, "Theme")
                }
                if settings.launcherEnabled {
                InterfaceSizeRow()
                SettingsRow(title: "Layout", anchor: .generalAppearance) {
                    LauncherPreviewPicker(
                        selection: $settings.compactMode, options: [false, true],
                        title: { $0 ? "Compact" : "Expanded" },
                        preview: { LayoutPreview(compact: $0) })
                }
                SettingsRow(title: "Tile style", anchor: .generalAppearance) {
                    LauncherPreviewPicker(
                        selection: $settings.launcherTileStyle,
                        options: LauncherTileStyle.allCases, title: \.title,
                        preview: { TileStylePreview(style: $0) })
                }
                Toggle(isOn: $settings.openOnCursorScreen) {
                    SettingsRowTitle(.generalAppearance, "Follow the cursor across displays")
                }
                Toggle(isOn: $settings.paletteDraggable) {
                    SettingsRowTitle(.generalAppearance, "Drag to reposition")
                    Text("Drag the strip above the search field.")
                }
                }
            } header: {
                SettingsSectionHeader(.generalAppearance)
            }

            if settings.launcherEnabled {
            Section {
                Picker(selection: $settings.rootSearchSensitivity) {
                    ForEach(SearchSensitivity.allCases) { sensitivity in
                        Text(sensitivity.title).tag(sensitivity)
                    }
                } label: {
                    SettingsRowTitle(.generalSearch, "Search sensitivity")
                    Text("Lower finds names from scattered letters.")
                }
                LabeledContent {
                    Button("Reset…", role: .destructive) {
                        confirmingRankingReset = true
                    }
                    .disabled(launcherRanking.isEmpty)
                } label: {
                    SettingsRowTitle(.generalSearch, "Learned ranking")
                    Text("Learned privately from the results you pick.")
                }
            } header: {
                SettingsSectionHeader(.generalSearch)
            }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.general)
        .confirmationDialog(
            "Reset learned launcher ranking?",
            isPresented: $confirmingRankingReset,
            titleVisibility: .visible
        ) {
            Button("Reset Ranking", role: .destructive) {
                launcherRanking.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ollie will relearn your preferred results as you use the launcher.")
        }
        .onAppear(perform: refreshInputSources)
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: InputSourceSwitcher.sourcesDidChange)
        ) { _ in
            refreshInputSources()
        }
    }

    private func refreshInputSources() {
        inputSources = core.inputSourceSwitcher.options(selecting: settings.autoSwitchInputSourceID)
    }
}

private struct LauncherPreviewPicker<Value: Hashable, Preview: View>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    @ViewBuilder let preview: (Value) -> Preview

    private var thumbnail: CGSize { Theme.Size.launcherSettingsPreview }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(options, id: \.self) { option in
                choice(option)
            }
        }
    }

    private func choice(_ option: Value) -> some View {
        let selected = selection == option
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
        return Button {
            selection = option
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                preview(option)
                    .frame(width: thumbnail.width, height: thumbnail.height)
                    .background(shape.fill(Theme.Colors.cardFill))
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(
                            selected ? Color.accentColor : Theme.Colors.separator,
                            lineWidth: selected ? Miniature.selectedRing : 1)
                    }
                Text(title(option))
                    .font(.caption)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PreviewChoiceButtonStyle())
        .accessibilityLabel(title(option))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private enum Miniature {
    static let selectedRing: CGFloat = 2
    static let inset: CGFloat = 6
    static let gap: CGFloat = 3
    static let pillHeight: CGFloat = 7
    static let cardRadius: CGFloat = 3
    static let cardIcon: CGFloat = 6
    static let cardIconRadius: CGFloat = 1.5
    static let cardIconSpacing: CGFloat = 4
    static let cardGrid = (rows: 2, columns: 4)
    static let icon: CGFloat = 10
    static let iconRadius: CGFloat = 2.5
    static let plate: CGFloat = 16
    static let tile = CGSize(width: 19, height: 30)
    static let tileRadius: CGFloat = 4
    static let tileSpacing: CGFloat = 2
    static let label = CGSize(width: 11, height: 2.5)
}

private struct LayoutPreview: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: Miniature.gap) {
            Capsule().fill(Theme.Colors.launcherPreviewMark).frame(height: Miniature.pillHeight)
            if !compact {
                RoundedRectangle(cornerRadius: Miniature.cardRadius, style: .continuous)
                    .fill(Theme.Colors.launcherPreviewSurface)
                    .overlay { icons }
            }
        }
        .padding(Miniature.inset)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var icons: some View {
        Grid(horizontalSpacing: Miniature.cardIconSpacing, verticalSpacing: Miniature.cardIconSpacing) {
            ForEach(0..<Miniature.cardGrid.rows, id: \.self) { _ in
                GridRow {
                    ForEach(0..<Miniature.cardGrid.columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Miniature.cardIconRadius, style: .continuous)
                            .fill(Theme.Colors.launcherPreviewMark)
                            .frame(width: Miniature.cardIcon, height: Miniature.cardIcon)
                    }
                }
            }
        }
    }
}

private struct TileStylePreview: View {
    let style: LauncherTileStyle

    private var highlight: some View {
        RoundedRectangle(cornerRadius: Miniature.tileRadius, style: .continuous)
            .fill(Theme.Colors.launcherPreviewSurface)
    }

    var body: some View {
        HStack(spacing: Miniature.tileSpacing) {
            tile(selected: false)
            tile(selected: true)
            tile(selected: false)
        }
    }

    private func tile(selected: Bool) -> some View {
        VStack(spacing: Miniature.gap) {
            RoundedRectangle(cornerRadius: Miniature.iconRadius, style: .continuous)
                .fill(Theme.Colors.launcherPreviewMark)
                .frame(width: Miniature.icon, height: Miniature.icon)
                .frame(width: Miniature.plate, height: Miniature.plate)
                .background {
                    if selected, style == .iconHighlight { highlight }
                }
            Capsule()
                .fill(Theme.Colors.launcherPreviewLabel)
                .frame(width: Miniature.label.width, height: Miniature.label.height)
        }
        .frame(width: Miniature.tile.width, height: Miniature.tile.height)
        .background {
            if selected, style == .fullTile { highlight }
        }
    }
}

private struct PreviewChoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressedLabel(configuration: configuration)
    }

    private struct PressedLabel: View {
        let configuration: ButtonStyle.Configuration
        @State private var showsPressed = false

        var body: some View {
            configuration.label
                .opacity(showsPressed ? 0.7 : 1)
                .task(id: configuration.isPressed) {
                    if configuration.isPressed {
                        try? await Task.sleep(for: .milliseconds(20))
                        guard !Task.isCancelled else { return }
                        showsPressed = true
                    } else {
                        showsPressed = false
                    }
                }
        }
    }
}

/// Three glyph steps read as a legend; a true-to-scale "Aa" would look identical at 1.1.
private struct InterfaceSizeRow: View {
    @Environment(AppSettings.self) private var settings

    private static let glyph: [InterfaceSize: CGFloat] = [
        .standard: 11, .large: 14, .larger: 17
    ]

    var body: some View {
        SettingsRow(
            title: "Interface size",
            subtitle: "Scales the launcher and its panels, not Settings.",
            anchor: .generalAppearance
        ) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(InterfaceSize.allCases) { size in
                    segment(size)
                }
            }
        }
    }

    private func segment(_ size: InterfaceSize) -> some View {
        let selected = settings.interfaceSize == size
        return Button {
            settings.interfaceSize = size
        } label: {
            Text("Aa")
                .font(.system(size: Self.glyph[size] ?? 13, weight: .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .settingsOptionSegment(isSelected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(size.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(size.title)
    }
}
