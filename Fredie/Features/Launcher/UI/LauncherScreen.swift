import SwiftUI

struct LauncherScreen: PaletteScreen {
    let appIndex: AppIndex
    let favorites: FavoritesStore
    let visibility: VisibilityStore
    let core: AppCore
    let vm: PaletteState
    /// Sampled by `openActions`, so Restart and Quit can't move while the menu is up.
    let running: Bool
    let openActions: () -> Void
    /// Called when an action reorders the list, so the highlight scrolls back into view.
    let scrollToFollow: () -> Void

    /// Resolved in `init`: the palette indexes this several times per event, so it can't recompute.
    let rows: [AppEntry]
    private let pinnedCount: Int
    private let showsGrid: Bool
    private let columns: Int

    init(
        appIndex: AppIndex, favorites: FavoritesStore, visibility: VisibilityStore, core: AppCore,
        vm: PaletteState, running: Bool, openActions: @escaping () -> Void,
        scrollToFollow: @escaping () -> Void
    ) {
        self.appIndex = appIndex
        self.favorites = favorites
        self.visibility = visibility
        self.core = core
        self.vm = vm
        self.running = running
        self.openActions = openActions
        self.scrollToFollow = scrollToFollow

        let columns = Self.columns(for: core.settings.interfaceSize.metrics)
        self.columns = columns
        // Listed even when hidden from search: the shortcut that opened it still has to be answered.
        let pinned = vm.argumentEntryID.flatMap(core.customCommands.command(entryID:))
            .map(AppEntry.init).flatMap { $0.name == vm.query ? $0 : nil }
        let results =
            pinned.map { AppIndex.Results(entries: [$0]) }
            ?? appIndex.appResults(
                query: vm.query, visibility: visibility, favorites: favorites,
                fallbackLimit: columns * 2)
        rows = results.entries
        pinnedCount = results.favoriteCount
        showsGrid = pinned == nil && vm.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func columns(for metrics: InterfaceMetrics) -> Int {
        max(Int((metrics.size.launcherWidth - metrics.spacing.md * 2) / metrics.size.appTile), 1)
    }

    private var clampedSelection: Int {
        rows.isEmpty ? 0 : min(max(vm.selection, 0), rows.count - 1)
    }

    var primaryActionTitle: String {
        entry(at: clampedSelection)?.kind.descriptor.openVerb ?? "Open Application"
    }

    private func entry(at selection: Int) -> AppEntry? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        guard showsGrid else { return nil }
        let grid = LauncherAppGrid(count: rows.count, columns: columns)
        switch axis {
        case .vertical: return grid.vertical(from: selection, by: delta)
        case .horizontal: return grid.horizontal(from: selection, by: delta)
        }
    }

    /// What the controls are is the owning feature's business; this only forwards.
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    {
        guard let entry = entry(at: selection), entry.kind == .customCommand else { return nil }
        return CustomCommandArgumentsAccessory.make(
            command: core.customCommands.command(entryID: entry.id), vm: vm,
            metrics: core.settings.interfaceSize.metrics, focus: focus,
            onSubmit: { activate(at: selection) })
    }

    private func argumentValues(for entry: AppEntry) -> [String: String] {
        guard entry.kind == .customCommand,
            let command = core.customCommands.command(entryID: entry.id)
        else { return [:] }
        return CustomCommandArgumentsAccessory.values(for: command, vm: vm)
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let app = entry(at: selection) else { return nil }
        return AppActionsMenu.content(
            app: app, searchQuery: vm.query, core: core, running: running,
            favorites: favoriteActions(for: app, at: selection),
            onResetRanking: {
                core.launcherCoordinator.resetRanking(for: app)
                if let index = rows.firstIndex(of: app) { vm.selection = index }
            },
            onHideFromSearch: { _ = hideFromSearch(at: selection) })
    }

    func activate(at selection: Int) {
        guard let app = entry(at: selection) else { return }
        launch(app)
    }

    private func launch(_ app: AppEntry) {
        core.launcherCoordinator.launch(app, searchQuery: vm.query, arguments: argumentValues(for: app))
    }

    func secondary(at selection: Int) -> Bool {
        guard !vm.isComposing else { return false }
        core.quickAICoordinator.askFromLauncher(vm.query)
        return true
    }

    func tertiary(at selection: Int) -> Bool {
        guard let app = entry(at: selection), app.canRevealInFinder else { return false }
        core.launcherCoordinator.showInFinder(app)
        return true
    }

    private func runningApplication(at selection: Int) -> AppEntry? {
        guard let app = entry(at: selection), app.kind == .application,
            core.runningApps.isRunning(app)
        else { return nil }
        return app
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .toggleFavorite: return toggleFavorite(at: selection)
        case .hideFromSearch: return hideFromSearch(at: selection)
        case .quit, .forceQuit: return quit(at: selection, force: shortcut == .forceQuit)
        case .restart: return restart(at: selection)
        case .favoriteSlot(let index): return launchSlot(at: index)
        default: return false
        }
    }

    /// ⌃⇧Q or ⌃⌥⇧Q — the screen owns the chord, but only a running app has anything to quit.
    private func quit(at selection: Int, force: Bool) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.quit(app, force: force)
        return true
    }

    /// ⌘R — mirrors the Restart Application row.
    private func restart(at selection: Int) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.restart(app)
        return true
    }

    private func toggleFavorite(at selection: Int) -> Bool {
        guard let app = entry(at: selection), !CommandCatalog.isQueryDriven(app) else { return false }
        let removed = favoriteIndex(of: app)
        favorites.toggle(app)
        guard showsGrid else { return true }
        selectFavorite(at: removed.map { $0 - 1 } ?? 0)
        return true
    }

    private func launchSlot(at index: Int) -> Bool {
        guard let app = rows.dropFirst(index).first else { return false }
        launch(app)
        return true
    }

    private var pinnedFavorites: ArraySlice<AppEntry> { showsGrid ? rows.prefix(pinnedCount) : [] }

    func moveFavorite(_ delta: Int, at selection: Int) -> Bool {
        guard let app = entry(at: selection), let index = favoriteIndex(of: app) else { return false }
        let target = index + delta
        guard target >= 0, target < pinnedFavorites.count else { return false }
        favorites.exchange(favorites.key(for: app), with: favorites.key(for: rows[target]))
        follow(app)
        return true
    }

    private func favoriteActions(
        for app: AppEntry, at selection: Int
    )
        -> AppActionsMenu.FavoriteActions
    {
        let index = favoriteIndex(of: app)
        return AppActionsMenu.FavoriteActions(
            isFavorite: favorites.isFavorite(app),
            canMoveUp: index.map { $0 > 0 } ?? false,
            canMoveDown: index.map { $0 < pinnedFavorites.count - 1 } ?? false,
            toggle: { _ = toggleFavorite(at: selection) },
            move: { _ = moveFavorite($0, at: selection) })
    }

    private func favoriteIndex(of app: AppEntry) -> Int? {
        guard let index = rows.firstIndex(of: app), index < pinnedFavorites.count else { return nil }
        return index
    }

    /// ⇧⌘H — the row leaves the list for good, so the highlight takes the place it vacated.
    private func hideFromSearch(at selection: Int) -> Bool {
        guard let app = entry(at: selection), app.canHideFromSearch,
            !CommandCatalog.isQueryDriven(app), let index = rows.firstIndex(of: app)
        else { return false }
        visibility.setItemVisible(false, for: app)
        select(row: min(index, max(reorderedResults().entries.count - 1, 0)))
        return true
    }

    private func follow(_ app: AppEntry) {
        guard let index = reorderedResults().entries.firstIndex(of: app) else { return }
        select(row: index)
    }

    private func selectFavorite(at index: Int) {
        let count = reorderedResults().entries.count
        select(row: min(max(index, 0), max(count - 1, 0)))
    }

    /// Re-read the order the change just invalidated; this warms the key the next render reads.
    private func reorderedResults() -> AppIndex.Results {
        appIndex.appResults(
            query: vm.query, visibility: visibility, favorites: favorites, fallbackLimit: columns * 2)
    }

    private func select(row index: Int) {
        vm.selection = index
        scrollToFollow()
    }

    /// The sample `openActions` takes; only an app row can ever carry the running-only actions.
    func isRunning(at selection: Int) -> Bool {
        guard let app = entry(at: selection) else { return false }
        return core.runningApps.isRunning(app)
    }

    /// The compact bar's icons: the first five favorites. The "…" that follows them is not one.
    var compactFavorites: [AppEntry] { Array(pinnedFavorites.prefix(5)) }

    /// Whether the compact bar's "…" has anything to reveal.
    var hasUnshownFavorites: Bool { pinnedFavorites.count > compactFavorites.count }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            LauncherList(
                results: rows,
                selectedRowID: entry(at: selection)?.id,
                layout: showsGrid ? .grid(columns: columns) : .list,
                scroll: scroll,
                onActivate: launch,
                onActions: { app in
                    if let index = rows.firstIndex(of: app) { vm.selection = index }
                    openActions()
                },
                onDropped: { core.paletteCoordinator.dragLanded() }))
    }
}
