import AppKit

@MainActor
final class SpaceSwitcher {
    nonisolated static let augmentsEvents = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))

    enum Result { case posted, blocked, unavailable }

    var speed: SpaceTransitionSpeed = .instant
    private lazy var api = SpaceSystemAPI()
    private var spaceObserver: NotificationToken?
    private var boundary = SpaceBoundaryState()
    private var gesture: Task<Void, Never>?

    func perform(_ direction: SpaceDirection) {
        guard Permissions.ensureAccessibility() else { return }
        _ = switchSpace(direction)
    }

    @discardableResult
    func switchSpace(_ direction: SpaceDirection) -> Result {
        guard gesture == nil else { return .blocked }
        guard Permissions.isAccessibilityTrusted(),
              let cursor = CGEvent(source: nil)?.location,
              let displays = api.displays(), let display = display(at: cursor, in: displays) else { return .unavailable }
        observeSpaceChanges()
        let now = ProcessInfo.processInfo.systemUptime
        guard let target = boundary.target(
            direction: direction, display: display.identifier, current: display.current, spaces: display.spaces, now: now
        ) else { return .blocked }
        guard let events = events(direction: direction, location: cursor) else {
            Diagnostics(category: "spaces").error("Could not create Space switch events")
            return .unavailable
        }
        boundary.record(target: target, display: display.identifier, spaces: display.spaces, now: now)
        let ramped = speed != .instant
        let delay = speed.rampDuration.map { $0 / 8 } ?? (Self.augmentsEvents ? SpaceGesture.phaseDelay : .zero)
        if delay == .zero {
            events.forEach { $0.post(tap: .cgSessionEventTap) }
        } else {
            gesture = Task { [weak self] in
                defer { self?.gesture = nil }
                guard !Task.isCancelled else { return }
                for (index, event) in events.dropLast().enumerated() {
                    guard !Task.isCancelled else { break }
                    event.post(tap: .cgSessionEventTap)
                    if !ramped || index > 0 {
                        do { try await Task.sleep(for: delay) } catch { break }
                    }
                }
                events.last?.post(tap: .cgSessionEventTap)
            }
        }
        return .posted
    }

    var canIntercept: Bool {
        guard Permissions.isAccessibilityTrusted(), let cursor = CGEvent(source: nil)?.location,
              let displays = api.displays(), let display = display(at: cursor, in: displays) else { return false }
        return display.spaces.contains(display.current)
    }

    func stop() {
        gesture?.cancel()
        spaceObserver = nil
        boundary.reset()
    }

    private func observeSpaceChanges() {
        guard spaceObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        spaceObserver = NotificationToken(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.boundary.reset() }
        }, center: center)
    }

    private func display(at point: CGPoint, in displays: [DisplaySpaces]) -> DisplaySpaces? {
        var displayID = CGDirectDisplayID()
        var count: UInt32 = 0
        if CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0,
           let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            let identifier = CFUUIDCreateString(nil, uuid) as String
            if let display = displays.first(where: { $0.identifier == identifier }) { return display }
        }
        return displays.count == 1 ? displays.first : nil
    }

    private func events(direction: SpaceDirection, location: CGPoint) -> [CGEvent]? {
        let direction = Self.augmentsEvents && Self.naturalScrolling ? direction.reversed : direction
        let sign = direction == .next ? 1.0 : -1.0
        let frames: [(SpaceGesture.Phase, Double?, Double?)]
        if speed == .instant {
            frames = SpaceGesture.Phase.allCases.map { ($0, nil, nil) }
        } else {
            var ramp: [(SpaceGesture.Phase, Double?, Double?)] = [(.began, 0, 0)]
            for step in 1...8 {
                let fraction = Double(step) / 8
                ramp.append((.changed, sign * 0.35 * fraction, sign * 130 * fraction))
            }
            ramp.append((.ended, sign * 0.35, sign * 130))
            frames = ramp
        }
        var events: [CGEvent] = []
        for (phase, progress, velocity) in frames {
            guard let event = Self.event(
                phase: phase, direction: direction, progress: progress, velocity: velocity
            ) else { return nil }
            event.location = location
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: Paster.ollieEventTag)
            events.append(event)
        }
        return events
    }

    private static var naturalScrolling: Bool {
        UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    }

    private static func event(
        phase: SpaceGesture.Phase, direction: SpaceDirection, progress: Double?, velocity: Double?
    ) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        let timestamp = mach_absolute_time()
        let fields = SpaceGesture.fields(
            phase: phase, direction: direction, augmented: augmentsEvents, timestamp: timestamp,
            progress: progress, velocity: velocity)
        for field in fields {
            guard let key = CGEventField(rawValue: field.raw) else { continue }
            switch field.value {
            case .integer(let value): event.setIntegerValueField(key, value: value)
            case .double(let value): event.setDoubleValueField(key, value: value)
            }
        }
        guard augmentsEvents else { return event }
        let payload = SpaceGesture.payload(
            phase: phase, direction: direction, timestamp: timestamp, progress: progress, velocity: velocity)
        guard var bytes = event.__data(allocator: nil) as Data?, bytes.starts(with: SpaceGesture.dataVersion) else { return nil }
        bytes.append(contentsOf: SpaceGesture.payloadRecordHeader(payloadCount: payload.count))
        bytes.append(payload)
        return CGEvent(withDataAllocator: nil, data: bytes as CFData)
    }
}
