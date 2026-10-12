import AppKit

@MainActor
final class KeystrokeMonitor {
    var includeMouseClicks = false
    var onInput: ((InputSoundEvent) -> Void)?
    var onRunningStateChanged: ((Bool) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeMouseClickSelection: Bool?

    private nonisolated static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<KeystrokeMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        if shouldReenableTap(for: type) {
            Task { @MainActor in
                monitor.reenableTap()
            }
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.eventSourceUserData) != Paster.fredieEventTag,
              let inputEvent = inputEvent(for: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }

        Task { @MainActor in
            guard monitor.isRunning else { return }
            monitor.onInput?(inputEvent)
        }

        return Unmanaged.passUnretained(event)
    }

    var isRunning: Bool {
        guard let eventTap else {
            return false
        }

        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    var needsRestartForInputSelection: Bool {
        isRunning && activeMouseClickSelection != includeMouseClicks
    }

    nonisolated static var hasInputMonitoringAccess: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    nonisolated static func requestInputMonitoringAccess() -> Bool {
        CGRequestListenEventAccess()
    }

    func start() -> Bool {
        stop()

        let mask = Self.eventMask(includeMouseClicks: includeMouseClicks)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        activeMouseClickSelection = includeMouseClicks
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        activeMouseClickSelection = nil
    }

    nonisolated static func shouldReenableTap(for type: CGEventType) -> Bool {
        type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
    }

    private func reenableTap() {
        guard let eventTap else {
            onRunningStateChanged?(false)
            return
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        onRunningStateChanged?(isRunning)
    }

    nonisolated private static func kind(for keyCode: Int) -> KeystrokeKind {
        switch keyCode {
        case 36, 76:
            .enter
        case 49:
            .space
        case 51, 117:
            .delete
        default:
            .character
        }
    }

    nonisolated private static func eventMask(includeMouseClicks: Bool) -> CGEventMask {
        var mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        if includeMouseClicks {
            mask |= (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
                | (1 << CGEventType.rightMouseDown.rawValue)
                | (1 << CGEventType.rightMouseUp.rawValue)
                | (1 << CGEventType.otherMouseDown.rawValue)
                | (1 << CGEventType.otherMouseUp.rawValue)
        }
        return CGEventMask(mask)
    }

    nonisolated private static func inputEvent(for type: CGEventType, event: CGEvent) -> InputSoundEvent? {
        switch type {
        case .keyDown, .keyUp:
            let phase: KeystrokePhase = type == .keyDown ? .down : .up
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            guard phase != .down || !isRepeat else {
                return nil
            }

            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            return .key(kind(for: keyCode), phase)
        case .leftMouseDown:
            return .mouse(.primary, .down)
        case .leftMouseUp:
            return .mouse(.primary, .up)
        case .rightMouseDown:
            return .mouse(.secondary, .down)
        case .rightMouseUp:
            return .mouse(.secondary, .up)
        case .otherMouseDown:
            return .mouse(.other, .down)
        case .otherMouseUp:
            return .mouse(.other, .up)
        default:
            return nil
        }
    }
}
