import AppKit

@MainActor
final class SpaceSwipeMonitor {
    private let switcher: SpaceSwitcher
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var state = SpaceSwipeState()

    init(switcher: SpaceSwitcher) { self.switcher = switcher }

    var isRunning: Bool { eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() {
        guard eventTap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<SpaceSwipeMonitor>.fromOpaque(context).takeUnretainedValue().handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: (1 << 29) | (1 << 30), callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil
        eventTap = nil
        state.reset()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            state.reset()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return passthrough
        }
        guard event.getIntegerValueField(.eventSourceUnixProcessID) == 0,
              event.getIntegerValueField(.eventSourceUserData) != Paster.ollieEventTag else { return passthrough }
        let eventType = event.getIntegerValueField(CGEventField(rawValue: 55)!)
        if eventType == 29 { return state.isTracking ? nil : passthrough }
        guard eventType == 30,
              event.getIntegerValueField(CGEventField(rawValue: 110)!) == 23,
              event.getIntegerValueField(CGEventField(rawValue: 123)!) == 1 else { return passthrough }
        let phase = event.getIntegerValueField(CGEventField(rawValue: 132)!)
        let sign = SpaceSwitcher.augmentsEvents ? -1.0 : 1.0
        var action = state.handle(
            phase: phase,
            progress: sign * event.getDoubleValueField(CGEventField(rawValue: 124)!),
            velocity: sign * event.getDoubleValueField(CGEventField(rawValue: 129)!),
            overlayActive: phase == 1 && (Self.isOverlayActive() || !switcher.canIntercept))
        if case .switchSpace(let direction) = action {
            switch switcher.switchSpace(direction) {
            case .posted: state.didPost(true)
            case .blocked: state.didPost(false)
            case .unavailable:
                state.reset()
                return passthrough
            }
            action = phase == 4 ? state.finish() : .suppress
        }
        switch action {
        case .pass: return passthrough
        case .finish where SpaceSwitcher.augmentsEvents:
            for field: UInt32 in [124, 129, 130] { event.setDoubleValueField(CGEventField(rawValue: field)!, value: 0) }
            return passthrough
        default: return nil
        }
    }

    private static func isOverlayActive() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let layers = windows.compactMap { window -> Int? in
            guard window[kCGWindowOwnerName as String] as? String == "Dock" else { return nil }
            return window[kCGWindowLayer as String] as? Int
        }
        return layers.contains(20) && (SpaceSwitcher.augmentsEvents || layers.contains(18))
    }
}
