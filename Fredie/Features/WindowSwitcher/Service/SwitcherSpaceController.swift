import AppKit
import ApplicationServices
import Darwin

struct DisplaySpaces {
    let identifier: String
    let current: UInt64
    let spaces: [UInt64]
}

struct SpaceSwitchPlan: Equatable {
    let display: String
    let target: UInt64
    let steps: Int

    static func make(windowSpaces: Set<UInt64>, displays: [DisplaySpaces]) -> Self? {
        guard !displays.contains(where: { windowSpaces.contains($0.current) }) else { return nil }
        for display in displays {
            guard let current = display.spaces.firstIndex(of: display.current),
                  let target = display.spaces.indices
                    .filter({ windowSpaces.contains(display.spaces[$0]) })
                    .min(by: { abs($0 - current) < abs($1 - current) }) else { continue }
            return Self(display: display.identifier, target: display.spaces[target], steps: target - current)
        }
        return nil
    }
}

@MainActor
final class SwitcherSpaceController {
    private let api = SpaceSystemAPI()
    private var pendingTransition: (id: UUID, task: Task<Bool, Never>)?

    func showWindow(_ windowID: CGWindowID) async {
        if let pendingTransition { _ = await pendingTransition.task.value }
        guard !Task.isCancelled,
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27,
              let displays = api.displays(),
              let spaces = api.spaces(for: windowID),
              let plan = SpaceSwitchPlan.make(windowSpaces: spaces, displays: displays),
              let location = location(for: plan.display) else { return }

        let started = ContinuousClock.now
        let id = UUID()
        let transition = Task { [api] in
            guard Self.postGesture(steps: plan.steps, location: location) else { return false }
            for _ in 0..<50 {
                try? await Task.sleep(for: .milliseconds(10))
                if api.displays()?.contains(where: {
                    $0.identifier == plan.display && $0.current == plan.target
                }) == true {
                    return true
                }
            }
            return false
        }
        pendingTransition = (id, transition)
        let arrived = await transition.value
        if pendingTransition?.id == id { pendingTransition = nil }
        Diagnostics(category: "window-switcher").benchmark(
            "focus.spaceSwitch", since: started,
            details: "steps=\(plan.steps) arrived=\(arrived)"
        )
        if !arrived {
            Diagnostics(category: "window-switcher").warning("focus.spaceSwitch failed", details: "target=\(plan.target)")
        }
    }

    private func location(for identifier: String) -> CGPoint? {
        for screen in NSScreen.screens {
            guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
                  CFUUIDCreateString(nil, uuid) as String == identifier || identifier == "Main" else { continue }
            let bounds = CGDisplayBounds(displayID)
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }
        return nil
    }

    private static func postGesture(steps: Int, location: CGPoint) -> Bool {
        let direction = steps > 0 ? 1.0 : -1.0
        let progress = direction * Double(Float.leastNonzeroMagnitude)
        let velocity = direction * 2000 * Double(abs(steps))
        var events: [CGEvent] = []
        for _ in 0..<abs(steps) {
            for phase: Int64 in [1, 2, 4] {
                guard let event = CGEvent(source: nil) else { return false }
                event.location = location
                event.flags = []
                event.setIntegerValueField(CGEventField(rawValue: 55)!, value: 30)
                event.setIntegerValueField(CGEventField(rawValue: 110)!, value: 23)
                event.setIntegerValueField(CGEventField(rawValue: 123)!, value: 1)
                event.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
                event.setDoubleValueField(CGEventField(rawValue: 124)!, value: progress)
                event.setDoubleValueField(CGEventField(rawValue: 129)!, value: velocity)
                event.setDoubleValueField(CGEventField(rawValue: 130)!, value: velocity)
                events.append(event)
            }
        }
        events.forEach { $0.post(tap: .cgSessionEventTap) }
        return true
    }
}

private struct SpaceSystemAPI {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplays = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopyWindowSpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private let connection: MainConnection?
    private let copyDisplays: CopyDisplays?
    private let copyWindowSpaces: CopyWindowSpaces?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        connection = Self.resolve("CGSMainConnectionID", in: handle)
        copyDisplays = Self.resolve("CGSCopyManagedDisplaySpaces", in: handle)
        copyWindowSpaces = Self.resolve("CGSCopySpacesForWindows", in: handle)
    }

    func displays() -> [DisplaySpaces]? {
        guard let connection, let copyDisplays,
              let raw = copyDisplays(connection())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return raw.compactMap { display in
            guard let identifier = display["Display Identifier"] as? String,
                  let current = display["Current Space"] as? [String: Any],
                  let currentID = current["id64"] as? NSNumber,
                  let spaces = display["Spaces"] as? [[String: Any]] else { return nil }
            return DisplaySpaces(
                identifier: identifier, current: currentID.uint64Value,
                spaces: spaces.compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            )
        }
    }

    func spaces(for windowID: CGWindowID) -> Set<UInt64>? {
        guard let connection, let copyWindowSpaces,
              let values = copyWindowSpaces(connection(), 7, [windowID] as CFArray)?.takeRetainedValue() as? [NSNumber]
        else { return nil }
        return Set(values.map(\.uint64Value))
    }

    private static func resolve<T>(_ symbol: String, in handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle, let address = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(address, to: T.self)
    }
}
