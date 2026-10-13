import SwiftUI

struct LauncherList: View {
    @Environment(\.metrics) private var metrics
    let results: [AppEntry]
    let selectedRowID: String?
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    let onDropped: () -> Void
    @Environment(RunningAppsMonitor.self) private var runningApps

    private var firstRowSelected: Bool {
        selectedRowID != nil && selectedRowID == results.first?.id
    }

    private var hasOverflow: Bool { results.count > 10 }

    var body: some View {
        Group {
            if results.isEmpty {
                EmptyResults(text: "No results")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        content
                            .padding(metrics.scaled(Theme.Size.paletteCardInset))
                            .hideNativeScrollers()
                            .scrollOriginAnchor()
                    }
                    .modifier(LauncherBottomFade(hasOverflow: hasOverflow))
                    .thinScrollbar()
                    .scrollFollowsSelection(
                        scroll, row: selectedRowID, atOrigin: firstRowSelected, proxy: proxy)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
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

    /// Cache-only icon: the row holds its own smaller bitmap, and a decode would stall the drag.
    private func drag(for app: AppEntry) -> RowDrag? {
        guard app.canDragOut else { return nil }
        return RowDrag(
            item: { .file(app.url, image: IconCache.cached(app.iconSource, fileURL: app.url)) },
            dropped: onDropped)
    }
}

private struct LauncherBottomFade: ViewModifier {
    @Environment(\.metrics) private var metrics
    @State private var remainingBelow: CGFloat = 0
    let hasOverflow: Bool

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentSize.height + geometry.contentInsets.bottom
                    - geometry.containerSize.height - geometry.contentOffset.y)
            } action: { _, distance in
                remainingBelow = distance
            }
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: hasOverflow ? min(remainingBelow, metrics.spacing.xl) : 0)
                }
                .ignoresSafeArea()
            }
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

private struct AppRow: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.metrics) private var metrics
    let app: AppEntry
    let selected: Bool
    let running: Bool
    let slot: Character?
    /// Observed so a hotkey set/cleared in Settings re-renders the row's keycaps immediately.
    @Environment(HotKeyManager.self) private var hotKeys
    /// Observed for the same reason: an alias edit re-renders the row's badge at once.
    @Environment(PaletteState.self) private var palette
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
            AppIconView(app: app, pointSize: metrics.scaled(Theme.Size.launcherListIcon))
                .frame(width: metrics.scaled(Theme.Size.launcherListIcon), height: metrics.scaled(Theme.Size.launcherListIcon))
                .overlay(alignment: .bottom) {
                    RunningDot(running: running).offset(y: 3)
                }
            Text(app.name)
                .font(.system(size: metrics.scaled(Theme.Size.launcherListFontSize)))
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
            } else if let slot, palette.commandHeld {
                Text(verbatim: "⌘" + String(slot))
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .frame(height: metrics.scaled(settings.paletteDensity.launcherRowHeight))
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}
