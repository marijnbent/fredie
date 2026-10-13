import AppKit
import Carbon
import ApplicationServices

enum SwitcherShortcutAction {
    case activate(
        reverse: Bool,
        windowScopeOverride: WindowScope?,
        triggeredAt: ContinuousClock.Instant
    )
    case moveSelection(delta: Int)
    case performSelectionAction(SwitcherSelectionAction)
    case confirmSelection
    case dismiss
    case openSettings
}

@MainActor
final class SwitcherShortcutMonitor {
    var onAction: ((SwitcherShortcutAction) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hasStarted = false
    private var isStarting = false
    private let settingsStore: SwitcherSettingsStore
    private let diagnostics = Diagnostics(category: "window-switcher")
    private let trackedModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
    private var activeCycleModifiers: NSEvent.ModifierFlags?
    private var isCycleActive = false

    init(settingsStore: SwitcherSettingsStore) {
        self.settingsStore = settingsStore
    }

    func start() {
        guard !isStarting else { return }
        isStarting = true
        defer {
            isStarting = false
            hasStarted = true
        }
        guard eventTap == nil else {
            diagnostics.info("shortcutMonitor.start skipped=alreadyRunning")
            return
        }

        diagnostics.info("shortcutMonitor.start")
        let hasListenAccess = CGPreflightListenEventAccess()
        guard hasListenAccess else {
            diagnostics.info("shortcutMonitor.waitingForListenAccess")
            return
        }

        installEventTap()
    }

    func retryIfNeeded() {
        guard hasStarted, !isStarting else { return }
        verifyEventTap()
    }

    private func installEventTap() {
        guard eventTap == nil else {
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<SwitcherShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            diagnostics.error("shortcutMonitor.tapCreate failed")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        diagnostics.info("shortcutMonitor.started")
    }

    var isRunning: Bool { eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func restart() {
        diagnostics.info("shortcutMonitor.restart")
        stop()
        start()
    }

    func stop() {
        diagnostics.info("shortcutMonitor.stop")
        hasStarted = false

        removeEventTap()
        activeCycleModifiers = nil
        isCycleActive = false
    }

    private func removeEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }

        eventTap = nil
        runLoopSource = nil
    }

    func endCycle() {
        if isCycleActive {
            diagnostics.info("shortcutMonitor.endCycle")
        }
        activeCycleModifiers = nil
        isCycleActive = false
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard event.getIntegerValueField(.eventSourceUserData) != Paster.fredieEventTag else { return Unmanaged.passUnretained(event) }
        let eventReceivedAt = ContinuousClock.now
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleDisabledTap(type: type)
            return Unmanaged.passUnretained(event)
        }

        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(trackedModifiers)

        if type == .flagsChanged {
            if isCycleActive, shouldConfirmSelection(for: modifiers) {
                endCycle()
                dispatch(.confirmSelection, reason: "modifierRelease")
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if isCycleActive, let action = panelAction(for: keyCode, modifiers: modifiers) {
            if action.endsCycle {
                endCycle()
            }
            dispatch(action, reason: "panel keyCode=\(keyCode) modifiers=\(modifiers.rawValue)")
            return nil
        }

        if let shortcut = activationAction(
            for: keyCode,
            modifiers: modifiers,
            triggeredAt: eventReceivedAt
        ) {
            dispatch(shortcut, reason: "activation keyCode=\(keyCode) modifiers=\(modifiers.rawValue)")
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func dispatch(_ action: SwitcherShortcutAction, reason: String) {
        diagnostics.info("shortcutMonitor.dispatch reason=\(reason)")
        onAction?(action)
    }

    private func handleDisabledTap(type: CGEventType) {
        diagnostics.warning("shortcutMonitor.tapDisabled", details: "type=\(type.rawValue)")
        guard let eventTap else {
            diagnostics.warning("shortcutMonitor.tapDisabled missingTap")
            replaceEventTapIfPermitted()
            return
        }

        guard CFMachPortIsValid(eventTap) else {
            diagnostics.warning("shortcutMonitor.tapDisabled invalidTap")
            replaceEventTapIfPermitted()
            return
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        if CGEvent.tapIsEnabled(tap: eventTap) {
            diagnostics.info("shortcutMonitor.tapReenabled type=\(type.rawValue)")
        } else {
            diagnostics.warning("shortcutMonitor.tapReenable failed", details: "type=\(type.rawValue)")
            replaceEventTapIfPermitted()
        }
    }

    private func verifyEventTap() {
        guard hasStarted, !isStarting else { return }
        guard let eventTap else {
            guard CGPreflightListenEventAccess() else {
                return
            }
            diagnostics.info("shortcutMonitor.health installingTap")
            installEventTap()
            return
        }

        guard CFMachPortIsValid(eventTap) else {
            diagnostics.warning("shortcutMonitor.health invalidTap replacing")
            replaceEventTapIfPermitted()
            return
        }

        guard !CGEvent.tapIsEnabled(tap: eventTap) else {
            return
        }

        diagnostics.warning("shortcutMonitor.health disabledTap reenabling")
        CGEvent.tapEnable(tap: eventTap, enable: true)
        if !CGEvent.tapIsEnabled(tap: eventTap) {
            diagnostics.warning("shortcutMonitor.health disabledTap replacing")
            replaceEventTapIfPermitted()
        }
    }

    private func replaceEventTapIfPermitted() {
        removeEventTap()
        guard CGPreflightListenEventAccess() else {
            return
        }
        installEventTap()
    }

    private func panelAction(for keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> SwitcherShortcutAction? {
        if Int(keyCode) == kVK_Escape {
            return .dismiss
        }

        switch Int(keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return .confirmSelection
        case kVK_ANSI_Comma:
            return .openSettings
        case kVK_ANSI_W:
            return .performSelectionAction(.closeWindow)
        case kVK_ANSI_Q:
            return .performSelectionAction(.quitApp)
        default:
            break
        }

        switch Int(keyCode) {
        case kVK_UpArrow, kVK_LeftArrow:
            return .moveSelection(delta: -1)
        case kVK_DownArrow, kVK_RightArrow:
            return .moveSelection(delta: 1)
        default:
            break
        }

        guard !modifiers.isEmpty else {
            return nil
        }

        if let activation = activationMatch(for: keyCode, modifiers: modifiers) {
            return .moveSelection(delta: activation.reverse ? -1 : 1)
        }

        return nil
    }

    private func activationAction(
        for keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        triggeredAt: ContinuousClock.Instant
    ) -> SwitcherShortcutAction? {
        guard let activation = activationMatch(for: keyCode, modifiers: modifiers) else {
            return nil
        }

        activeCycleModifiers = activation.cycleModifiers
        isCycleActive = true
        diagnostics.info("shortcutMonitor.activate reverse=\(activation.reverse) cycleModifiers=\(activation.cycleModifiers.rawValue)")
        return .activate(
            reverse: activation.reverse,
            windowScopeOverride: activation.windowScopeOverride,
            triggeredAt: triggeredAt
        )
    }

    private func shouldConfirmSelection(for modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let activeCycleModifiers else {
            return false
        }

        let currentCycleModifiers = modifiers.subtracting(.shift)
        let shouldConfirm = currentCycleModifiers.intersection(activeCycleModifiers) != activeCycleModifiers
        if shouldConfirm {
            self.activeCycleModifiers = nil
            diagnostics.info("shortcutMonitor.shouldConfirmSelection modifiers=\(modifiers.rawValue)")
        }

        return shouldConfirm
    }

    private func activationMatch(for keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ActivationMatch? {
        if let shortcut = settingsStore.settings.activationShortcuts.first(where: { $0.matches(keyCode: keyCode, modifiers: modifiers) }) {
            return ActivationMatch(
                reverse: false,
                cycleModifiers: shortcut.requiredCycleModifiers,
                windowScopeOverride: shortcut.defaultWindowScope
            )
        }

        if let shortcut = settingsStore.settings.activationShortcuts.first(where: { shortcut in
            shortcut.matchesReverseActivator(keyCode: keyCode, modifiers: modifiers)
        }) {
            return ActivationMatch(
                reverse: true,
                cycleModifiers: shortcut.requiredCycleModifiers,
                windowScopeOverride: shortcut.defaultWindowScope
            )
        }

        if settingsStore.settings.reverseShortcut.matches(keyCode: keyCode, modifiers: modifiers) {
            return ActivationMatch(
                reverse: true,
                cycleModifiers: modifiers.subtracting(.shift),
                windowScopeOverride: settingsStore.settings.reverseShortcut.defaultWindowScope
            )
        }

        return nil
    }
}

private extension SwitcherShortcutAction {
    var endsCycle: Bool {
        switch self {
        case .confirmSelection, .dismiss, .openSettings:
            true
        case .activate, .moveSelection, .performSelectionAction:
            false
        }
    }
}

private struct ActivationMatch {
    let reverse: Bool
    let cycleModifiers: NSEvent.ModifierFlags
    let windowScopeOverride: WindowScope?
}

private extension SwitcherShortcut {
    var requiredCycleModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(modifiers)).intersection([.command, .option, .control])
    }

    func matchesReverseActivator(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        let expected = NSEvent.ModifierFlags(rawValue: UInt(self.modifiers)).intersection(relevant).union(.shift)
        let sanitized = modifiers.intersection(relevant)
        return self.keyCode == keyCode && sanitized == expected
    }
}
