import AppKit

/// Owns the Apple Shortcuts flow: discovery into the launcher slice, and the one run funnel.
@MainActor
@Observable
final class AppleShortcutCoordinator {
    /// Every row draws the Shortcuts app's icon, so one cached bitmap serves the whole list.
    static let applicationURL =
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts")
        ?? URL(fileURLWithPath: "/System/Applications/Shortcuts.app")

    /// The discovered library as rows, rebuilt only when the list itself changes.
    private(set) var entries: [AppEntry] = []

    private let settings: AppSettings
    private let appIndex: AppIndex
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    /// Nil until a read succeeds, so the first one after launch always sweeps.
    @ObservationIgnored private var shortcuts: [AppleShortcut]?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var runs: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var refreshGeneration = 0

    init(
        settings: AppSettings, appIndex: AppIndex, hotKeys: HotKeyManager,
        favorites: FavoritesStore, visibility: VisibilityStore, ranking: LauncherRankingStore,
        aliases: AliasStore, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func name(of id: UUID) -> String? {
        shortcuts?.first { $0.id == id }?.name
    }

    // MARK: - Feature presence

    /// Off forgets the library but frees nothing: only a successful read may say what is gone.
    func applyPresence() {
        guard settings.allows(.appleShortcuts) else {
            refreshGeneration += 1
            refreshTask?.cancel()
            refreshTask = nil
            runs.values.forEach { $0.cancel() }
            runs.removeAll()
            shortcuts = nil
            entries = []
            appIndex.setAppleShortcuts([])
            return
        }
        refresh()
    }

    /// Re-read on every launcher open; the tool answers in milliseconds, so overlaps just drop.
    func refresh() {
        guard settings.allows(.appleShortcuts), refreshTask == nil else { return }
        refreshGeneration += 1
        let revision = refreshGeneration
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { if revision == refreshGeneration { refreshTask = nil } }
            let found = try? await AppleShortcutRunner.list()
            // A failed read keeps the last good library, and with it every alias and binding.
            guard !Task.isCancelled, revision == refreshGeneration, let found,
                  settings.allows(.appleShortcuts), found != shortcuts else { return }
            shortcuts = found
            entries = found.map { AppEntry($0, applicationURL: Self.applicationURL) }
            appIndex.setAppleShortcuts(entries)
            removeReferences(toShortcutsMissingFrom: found)
        }
    }

    /// Frees what a deleted shortcut held, including one deleted while Ollie wasn't running.
    private func removeReferences(toShortcutsMissingFrom live: [AppleShortcut]) {
        let keys =
            Array(aliases.aliases.keys) + favorites.keys + visibility.hiddenItemKeys
            + ranking.visits.keys
        let bound = Set(hotKeys.boundAppleShortcutIDs)
        let stale = AppleShortcut.staleIDs(referencedBy: keys, bound: bound, live: live)
        guard !stale.isEmpty else { return }
        for id in stale.intersection(bound) {
            let action = HotKeyAction.appleShortcut(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        let entryIDs = Set(stale.map(AppleShortcut.entryID(for:)))
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs {
            ranking.reset(itemKey: entryID)
        }
    }

    // MARK: - Running

    /// The one funnel for a launcher row and a global shortcut, so the switch can't be bypassed.
    func run(id: UUID) {
        guard settings.allows(.appleShortcuts) else { return }
        // Focus goes back first: a shortcut usually acts on whatever the user was in.
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette() }
        let name = name(of: id) ?? "Shortcut"
        let runID = UUID()
        runs[runID] = Task { [weak self] in
            guard let self, !Task.isCancelled, settings.allows(.appleShortcuts) else { return }
            defer { runs[runID] = nil }
            do throws(AppleShortcutRunner.Failure) {
                try await AppleShortcutRunner.run(id: id)
            } catch {
                guard !Task.isCancelled, settings.allows(.appleShortcuts) else { return }
                await core.showNotice(
                    title: "Couldn’t Run \(name)", message: error.localizedDescription,
                    symbol: AppleShortcut.sfSymbol, tone: .danger)
            }
        }
    }

    func openShortcutsApp() {
        AppLauncher.launch(Self.applicationURL)
    }
}
