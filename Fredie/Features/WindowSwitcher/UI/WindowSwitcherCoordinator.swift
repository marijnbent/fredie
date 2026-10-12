import AppKit
import Observation

@MainActor
@Observable
final class WindowSwitcherCoordinator: HealthCheckable {
    let settingsStore = SwitcherSettingsStore()
    private unowned let core: AppCore
    private let ticker: HealthTicker
    @ObservationIgnored private let windowDiscovery = WindowDiscovery()
    @ObservationIgnored private let focusController = FocusController()
    @ObservationIgnored private let panelController = SwitcherPanelController()
    @ObservationIgnored private let failureFeedback = SwitcherFailureFeedback()
    private let diagnostics = SwitcherDiagnostics()
    @ObservationIgnored private lazy var shortcutMonitor = SwitcherShortcutMonitor(settingsStore: settingsStore)
    @ObservationIgnored private var workspaceActivationObserver: NotificationToken?
    @ObservationIgnored private var workspaceSpaceObserver: NotificationToken?
    @ObservationIgnored private var pendingInventoryRefresh: Task<Void, Never>?
    @ObservationIgnored private var pendingActionRefresh: Task<Void, Never>?
    @ObservationIgnored private let activation = SwitcherActivation()
    private var originalItem: SwitcherItem?
    private var monitoredActivationShortcuts: [SwitcherShortcut] = []
    private var monitoredReverseShortcut: SwitcherShortcut?
    private(set) var isRunning = false
    private(set) var conflict: String?
    var isCapturingShortcut = false { didSet { apply() } }

    init(core: AppCore, ticker: HealthTicker) {
        self.core = core
        self.ticker = ticker
        windowDiscovery.onInventoryChanged = { [weak self] in self?.scheduleVisibleInventoryRefresh() }
        panelController.onConfirm = { [weak self] item in self?.confirm(item) }
        panelController.onSelectionChanged = { [weak self] item in self?.preview(item) }
        activation.onChange = { [weak self] in
            guard let self else { return }
            updateInteractionState()
            guard !activation.isPending else { return }
            panelController.restoreVisibility()
            refreshVisibleSwitcherFromCache()
        }
        activation.onFailure = { [weak self] item in self?.failureFeedback.show(for: item) }
        shortcutMonitor.onAction = { [weak self] action in self?.handle(action) }
    }

    var reservedBindings: [HotKeyBinding] {
        guard core.settings.windowSwitcherEnabled else { return [] }
        let settings = settingsStore.settings
        let shortcuts = settings.activationShortcuts + [settings.reverseShortcut]
        return shortcuts.flatMap { shortcut -> [HotKeyBinding] in
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(shortcut.modifiers))
            return [modifiers, modifiers.union(.shift)].compactMap {
                KeyShortcut(keyCode: Int(shortcut.keyCode), modifierFlags: $0).map(HotKeyBinding.combo)
            }
        }
    }

    func apply() {
        let preferences = core.settings
        settingsStore.settings = SwitcherSettings(
            activationShortcuts: (preferences.switcherCommandTab ? [.commandTab] : []) + (preferences.switcherCommandBacktick ? [.commandBacktick] : []),
            windowSource: WindowSource(rawValue: preferences.switcherWindowSource) ?? .allSpaces,
            minimizedMode: VisibilityMode(rawValue: preferences.switcherMinimizedMode) ?? .doNotShow,
            hiddenMode: VisibilityMode(rawValue: preferences.switcherHiddenMode) ?? .doNotShow,
            appsWithoutWindowsMode: VisibilityMode(rawValue: preferences.switcherAppsWithoutWindowsMode) ?? .showAtBottom,
            switchWindowsImmediately: preferences.switcherImmediatePreview,
            diagnosticsEnabled: preferences.switcherDiagnostics)
        diagnostics.setEnabled(settingsStore.settings.diagnosticsEnabled)
        conflict = reservedBindings.compactMap {
            core.hotKeys.conflictOwner(of: $0, includeReservations: false)
        }.first
        guard core.settings.windowSwitcherEnabled,
              !isCapturingShortcut, conflict == nil else { stop(); return }
        ticker.subscribe(self)
        guard AXIsProcessTrusted(), CGPreflightListenEventAccess() else {
            stopRuntime()
            return
        }
        if !isRunning {
            observeWorkspaceActivation()
            windowDiscovery.startRegistry()
            windowDiscovery.recordActivation(of: NSWorkspace.shared.frontmostApplication)
            isRunning = true
        }
        if settingsStore.settings.activationShortcuts != monitoredActivationShortcuts ||
            settingsStore.settings.reverseShortcut != monitoredReverseShortcut || !shortcutMonitor.isRunning {
            monitoredActivationShortcuts = settingsStore.settings.activationShortcuts
            monitoredReverseShortcut = settingsStore.settings.reverseShortcut
            shortcutMonitor.restart()
        }
    }

    func healthCheck() {
        guard core.settings.windowSwitcherEnabled else { return }
        if !isRunning || !shortcutMonitor.isRunning || !AXIsProcessTrusted() { apply() }
    }

    func requestAccess() {
        CGRequestListenEventAccess()
        Permissions.openAccessibilitySettings()
    }

    func stop() {
        ticker.unsubscribe(self)
        stopRuntime()
    }

    private func stopRuntime() {
        shortcutMonitor.stop()
        dismissSwitcher(restoreFocus: false)
        windowDiscovery.stopRegistry()
        pendingInventoryRefresh?.cancel()
        pendingInventoryRefresh = nil
        pendingActionRefresh?.cancel()
        pendingActionRefresh = nil
        activation.cancel()
        failureFeedback.hide()
        workspaceActivationObserver = nil
        workspaceSpaceObserver = nil
        isRunning = false
    }

    private func handle(_ action: SwitcherShortcutAction) {
        diagnostics.info("shortcut.action \(action.diagnosticName)")
        switch action {
        case .activate(let reverse, let windowScopeOverride, let triggeredAt):
            openSwitcher(
                reverse: reverse,
                advanceInitialSelection: true,
                windowScopeOverride: windowScopeOverride,
                benchmarkStart: triggeredAt
            )
        case .moveSelection(let delta):
            panelController.moveSelection(delta: delta)
        case .performSelectionAction(let action):
            performSelectionAction(action)
        case .confirmSelection:
            if panelController.currentSelectedItem == nil {
                dismissSwitcher()
            } else {
                panelController.confirmSelection()
            }
        case .dismiss:
            dismissSwitcher()
        case .openSettings:
            dismissSwitcher(restoreFocus: false)
            showSettingsWindow()
        }
    }

    private func openSwitcher(
        reverse: Bool,
        advanceInitialSelection: Bool,
        windowScopeOverride: WindowScope? = nil,
        benchmarkStart: ContinuousClock.Instant
    ) {
        activation.cancel()
        failureFeedback.hide()
        let effectiveWindowScope = windowScopeOverride ?? .allApps
        diagnostics.info(
            "switcher.open reverse=\(reverse) advanceInitialSelection=\(advanceInitialSelection) scope=\(effectiveWindowScope.diagnosticName)"
        )
        let items = diagnostics.measure("switcher.snapshot", thresholdMilliseconds: 0) {
            windowDiscovery.snapshot(settings: settingsStore.settings, windowScope: effectiveWindowScope)
        }
        diagnostics.info("switcher.items count=\(items.count) first=\(items.first?.diagnosticSummary ?? "none")")
        originalItem = items.first
        windowDiscovery.beginPreview(from: originalItem)
        let panelStart = ContinuousClock.now
        let panelMetrics = panelController.show(items: items, selectedIndex: 0)
        updateInteractionState()
        let panelMilliseconds = SwitcherDiagnostics.elapsedMilliseconds(since: panelStart)
        let shortcutMilliseconds = SwitcherDiagnostics.elapsedMilliseconds(since: benchmarkStart)
        Task { @MainActor [diagnostics] in
            let nextRunLoopMilliseconds = SwitcherDiagnostics.elapsedMilliseconds(since: benchmarkStart)
            diagnostics.benchmark(
                "switcher.shortcutToNextRunLoop",
                durationMilliseconds: nextRunLoopMilliseconds,
                details: "items=\(items.count)"
            )
        }
        diagnostics.benchmark(
            "switcher.panelShow",
            durationMilliseconds: panelMilliseconds,
            details: "items=\(items.count) \(panelMetrics.benchmarkDetails)"
        )
        diagnostics.benchmark(
            "switcher.shortcutToPanelOrdered",
            durationMilliseconds: shortcutMilliseconds,
            details: "items=\(items.count)"
        )
        windowDiscovery.refreshAfterPanelOpen()
        guard advanceInitialSelection, items.count > 1 else {
            if let item = panelController.currentSelectedItem { preview(item) }
            return
        }

        panelController.moveSelection(delta: reverse ? -1 : 1)
    }

    private func performSelectionAction(_ action: SwitcherSelectionAction) {
        guard panelController.isVisible, let item = panelController.currentSelectedItem else {
            diagnostics.warning("selectionAction.missingSelection action=\(action.diagnosticName)")
            return
        }

        diagnostics.info("selectionAction.perform action=\(action.diagnosticName) item=\(item.diagnosticSummary)")
        switch action {
        case .activate:
            activate(item)
        case .closeWindow:
            Task { [weak self] in
                guard let self else { return }
                await focusController.closeWindow(for: item)
                refreshVisibleSwitcher(afterPerforming: action, targetItem: item)
            }
            return
        case .quitApp:
            focusController.quitApp(for: item)
        }

        refreshVisibleSwitcher(afterPerforming: action, targetItem: item)
    }

    private func preview(_ item: SwitcherItem) {
        guard settingsStore.settings.switchWindowsImmediately else { return }
        activate(item)
    }

    private func activate(_ item: SwitcherItem, confirming: Bool = false) {
        activation.activate(item, confirming: confirming) { [weak self] item async throws(CancellationError) in
            guard let self else { return nil }
            let order = windowDiscovery.beginActivation(of: item)
            var activated: SwitcherItem?
            defer {
                windowDiscovery.finishActivation(of: item, order: order, activated: Task.isCancelled ? nil : activated)
            }
            activated = try await focusController.activate(item, refreshTarget: windowDiscovery.refreshTarget)
            return activated
        }
    }

    private func confirm(_ item: SwitcherItem) {
        defer { updateInteractionState() }
        diagnostics.info("panel.confirm \(item.diagnosticSummary)")
        panelController.hide()
        shortcutMonitor.endCycle()
        windowDiscovery.endPreview()
        originalItem = nil
        if !activation.isPending, activation.previewedItem?.hasSameIdentity(as: item) == true {
            let order = windowDiscovery.beginActivation(of: item)
            windowDiscovery.finishActivation(of: item, order: order, activated: item)
        } else {
            activate(item, confirming: true)
        }
    }

    private func dismissSwitcher(restoreFocus: Bool = true) {
        defer { updateInteractionState() }
        failureFeedback.hide()
        panelController.hide()
        shortcutMonitor.endCycle()
        let hadPreview = activation.pendingItem != nil || activation.previewedItem != nil
        activation.cancel()
        windowDiscovery.endPreview()
        let restore = originalItem
        originalItem = nil
        if restoreFocus, settingsStore.settings.switchWindowsImmediately || hadPreview, let restore {
            activate(restore)
        }
    }

    private func updateInteractionState() {
        windowDiscovery.setInteractionState(
            panelOpen: panelController.isVisible,
            activationPending: activation.isPending
        )
    }

    private func refreshVisibleSwitcher(
        afterPerforming action: SwitcherSelectionAction,
        targetItem: SwitcherItem,
        attemptsRemaining: Int = 4
    ) {
        guard panelController.isVisible else {
            return
        }

        diagnostics.info(
            "switcher.refresh action=\(action.diagnosticName) attemptsRemaining=\(attemptsRemaining) target=\(targetItem.diagnosticSummary)"
        )
        let items = previewInventory()
        if items.isEmpty {
            diagnostics.warning("switcher.refresh emptySnapshot")
            dismissSwitcher()
            return
        }

        if action != .activate, attemptsRemaining > 0, items.contains(where: { $0.hasSameIdentity(as: targetItem) }) {
            pendingActionRefresh?.cancel()
            pendingActionRefresh = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                self?.refreshVisibleSwitcher(
                    afterPerforming: action,
                    targetItem: targetItem,
                    attemptsRemaining: attemptsRemaining - 1
                )
            }
            return
        }

        panelController.updateItemsPreservingSelection(items)
        if panelController.currentSelectedItem == nil { dismissSwitcher() }
        diagnostics.info("switcher.refresh updated count=\(items.count)")
    }

    private func scheduleVisibleInventoryRefresh() {
        guard panelController.isVisible, pendingInventoryRefresh == nil else {
            return
        }

        pendingInventoryRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else {
                return
            }
            self.pendingInventoryRefresh = nil
            self.refreshVisibleSwitcherFromCache()
        }
    }

    private func refreshVisibleSwitcherFromCache() {
        guard panelController.isVisible else {
            return
        }

        let items = previewInventory()
        panelController.updateItemsPreservingSelection(items)
        if panelController.currentSelectedItem == nil { dismissSwitcher() }
    }

    private func previewInventory() -> [SwitcherItem] {
        var settings = settingsStore.settings
        settings.windowSource = .allSpaces
        return windowDiscovery.snapshot(settings: settings, windowScope: .allApps)
    }

    private func showSettingsWindow() {
        failureFeedback.hide()
        core.settingsCoordinator.showSettings(tab: .windowSwitcher)
    }

    private func observeWorkspaceActivation() {
        diagnostics.info("workspaceActivation.observe")
        workspaceActivationObserver = NotificationToken(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                self?.diagnostics.info(
                    "workspaceActivation.didActivate app=\(app?.diagnosticName ?? "unknown") pid=\(app?.processIdentifier.description ?? "unknown")"
                )
                self?.windowDiscovery.recordActivation(of: app)
                self?.panelController.restoreVisibility()
            }
        }, center: NSWorkspace.shared.notificationCenter)
        workspaceSpaceObserver = NotificationToken(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.panelController.restoreVisibility(afterSpaceChange: true)
            }
        }, center: NSWorkspace.shared.notificationCenter)
    }
}

private extension SwitcherShortcutAction {
    var diagnosticName: String {
        switch self {
        case .activate(let reverse, let windowScopeOverride, _):
            "activate(reverse=\(reverse),scope=\((windowScopeOverride ?? .allApps).diagnosticName))"
        case .moveSelection(let delta):
            "moveSelection(delta=\(delta))"
        case .performSelectionAction(let action):
            "performSelectionAction(\(action.diagnosticName))"
        case .confirmSelection:
            "confirmSelection"
        case .dismiss:
            "dismiss"
        case .openSettings:
            "openSettings"
        }
    }
}

private extension SwitcherSelectionAction {
    var diagnosticName: String {
        switch self {
        case .activate:
            "activate"
        case .closeWindow:
            "closeWindow"
        case .quitApp:
            "quitApp"
        }
    }
}

private extension WindowScope {
    var diagnosticName: String {
        switch self {
        case .allApps:
            "allApps"
        case .activeApp:
            "activeApp"
        }
    }
}

private extension SwitcherItem {
    var diagnosticSummary: String {
        "kind=\(kind.diagnosticName) app=\(appName) pid=\(runningApplication.processIdentifier) title=\(displayTitle) hidden=\(isHidden) minimized=\(isMinimized)"
    }
}

private extension SwitcherItemKind {
    var diagnosticName: String {
        switch self {
        case .appOnly:
            "appOnly"
        case .window:
            "window"
        }
    }
}

private extension NSRunningApplication {
    var diagnosticName: String {
        localizedName ?? bundleIdentifier ?? "pid-\(processIdentifier)"
    }
}
