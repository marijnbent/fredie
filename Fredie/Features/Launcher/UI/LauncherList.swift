import SwiftUI

struct LauncherList: View {

    @Environment(\.metrics) private var metrics
    let results: [AppEntry]
    let selectedRowID: String?
    let layout: Layout
    let tileStyle: LauncherTileStyle
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    let onDropped: () -> Void
    @Environment(RunningAppsMonitor.self) private var runningApps

    enum Layout: Equatable {
        case grid(columns: Int)
        case list
    }

    private var firstRowSelected: Bool {
        selectedRowID != nil && selectedRowID == results.first?.id
    }

    var body: some View {
        Group {
            if results.isEmpty {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        content
                            .padding(metrics.spacing.md)
                            .hideNativeScrollers()
                            .scrollOriginAnchor()
                    }
                    .edgeDissolve()
                    .thinScrollbar()
                    .scrollFollowsSelection(
                        scroll, row: selectedRowID, atOrigin: firstRowSelected, proxy: proxy)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .grid(let columns):
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: metrics.spacing.xs),
                    count: max(columns, 1)),
                spacing: metrics.spacing.xs
            ) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                    AppTile(
                        app: app, selected: app.id == selectedRowID,
                        running: runningApps.isRunning(app), slot: FavoriteSlots.digit(at: index),
                        style: tileStyle
                    )
                    .contentShape(RoundedRectangle(cornerRadius: metrics.radius.appTile, style: .continuous))
                    .onRowTap(drag: drag(for: app)) { onActivate(app) }
                    .onRightClick { onActions(app) }
                    .selectionFrame(app.id == selectedRowID)
                }
            }
        case .list:
            LazyVStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                    AppRow(
                        app: app, selected: app.id == selectedRowID,
                        running: runningApps.isRunning(app), slot: FavoriteSlots.digit(at: index)
                    )
                    .contentShape(Rectangle())
                    .onRowTap(drag: drag(for: app)) { onActivate(app) }
                    .onRightClick { onActions(app) }
                    .selectionFrame(app.id == selectedRowID)
                }
            }
        }
    }

    /// Cache-only icon: the row holds its own smaller bitmap, and a decode would stall the drag.
    private func drag(for app: AppEntry) -> RowDrag? {
        guard app.canDragOut else { return nil }
        return RowDrag(
            item: { .file(app.url, image: IconCache.cached(app.iconSource, fileURL: app.url)) },
            dropped: onDropped)
    }
}

private struct RunningDot: View {
    let running: Bool

    var body: some View {
        Circle()
            .fill(.secondary)
            .frame(width: 3, height: 3)
            .opacity(running ? 1 : 0)
    }
}

private struct AppTile: View {

    @Environment(\.metrics) private var metrics
    let app: AppEntry
    let selected: Bool
    let running: Bool
    let slot: Character?
    let style: LauncherTileStyle
    @Environment(PaletteState.self) private var palette
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var plate: CGFloat { metrics.size.appTileIcon + metrics.spacing.md * 2 }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.appTile, style: .continuous)
    }

    var body: some View {
        VStack(spacing: metrics.spacing.xs) {
            AppIconView(app: app, pointSize: metrics.size.appTileIcon)
                .frame(width: metrics.size.appTileIcon, height: metrics.size.appTileIcon)
                .frame(width: plate, height: plate)
                .background(shape.fill(style == .iconHighlight ? fill : .clear))
                .overlay(alignment: .bottom) {
                    RunningDot(running: running).padding(.bottom, metrics.spacing.xxs)
                }
                .overlay(alignment: .topTrailing) {
                    if let slot, palette.commandHeld {
                        HStack(spacing: metrics.spacing.xxs) {
                            KeyCapChip(text: "⌘", style: .outline)
                            KeyCapChip(text: String(slot), style: .outline)
                        }
                        .fixedSize()
                        .alignmentGuide(.trailing) { $0[.leading] + $0.width / 2 }
                    }
                }
            Text(app.name)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(selected ? Color.primary : Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .allowsTightening(true)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, metrics.spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .frame(height: metrics.size.launcherTileHeight)
        .background(shape.fill(style == .fullTile ? fill : .clear))
        .armedHover($hovered)
    }
}

private struct AppRow: View {

    @Environment(\.metrics) private var metrics
    let app: AppEntry
    let selected: Bool
    let running: Bool
    let slot: Character?
    /// Observed so a hotkey set/cleared in Settings re-renders the row's keycaps immediately.
    @Environment(HotKeyManager.self) private var hotKeys
    /// Observed for the same reason: an alias edit re-renders the row's badge at once.
    @Environment(AliasStore.self) private var aliases
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var shortcutCaps: [String]? {
        guard let action = app.hotKeyAction else { return nil }
        return hotKeys.binding(for: action)?.keycaps
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            AppIconView(app: app, pointSize: metrics.size.resultRowIcon)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                .overlay(alignment: .bottom) {
                    RunningDot(running: running).offset(y: 3)
                }
            Text(app.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            if let subtitle = app.subtitle {
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let alias = aliases.alias(for: app.preferenceKey) {
                Text(alias)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, metrics.spacing.sm)
                    .padding(.vertical, metrics.spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                            .fill(Theme.Colors.controlSurface))
            }
            if let caps = shortcutCaps {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
            Spacer()
            if selected {
                Text("↩")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Color.accentColor)
            } else if let slot {
                Text(verbatim: "⌘" + String(slot))
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .frame(height: metrics.size.launcherRowHeight)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}
