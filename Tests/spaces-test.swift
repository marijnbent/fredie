import Foundation

@main
struct SpacesTests {
    static func main() {
        var swipe = SpaceSwipeState()
        func event(_ phase: Int64, _ progress: Double = 0, _ velocity: Double = 0, overlay: Bool = false) -> SpaceSwipeState.Action {
            swipe.handle(phase: phase, progress: progress, velocity: velocity, overlayActive: overlay)
        }
        expect(event(2, 0.3) == .pass, "untracked change passes through")
        expect(event(8) == .pass, "untracked cancellation passes through")
        expect(event(1, overlay: true) == .pass, "Mission Control retains native gestures")
        expect(event(2, 0.3) == .pass, "Mission Control changes remain native")
        expect(event(1) == .suppress, "begin starts interception")
        expect(event(2) == .suppress, "zero progress waits for direction")
        expect(event(2, 0.2) == .switchSpace(.next), "positive progress moves right")
        swipe.didPost(true)
        expect(event(2, -0.2) == .suppress, "one switch per physical swipe")
        expect(event(4) == .finish, "posted swipe completes Dock state")
        expect(!swipe.isTracking, "end clears tracking")
        _ = event(1)
        expect(event(4, 0, -0.5) == .switchSpace(.previous), "end velocity supplies missing direction")
        swipe.didPost(true)
        expect(swipe.finish() == .finish && !swipe.isTracking, "velocity fallback also finishes")
        _ = event(1)
        _ = event(2, 1)
        swipe.didPost(false)
        expect(event(4) == .suppress, "edge swipe never bounces back")
        _ = event(1)
        expect(event(4) == .pass, "no direction leaves the terminal event native")
        _ = event(1)
        expect(event(2, .nan) == .suppress, "invalid motion cannot trigger a switch")
        expect(event(8) == .suppress && !swipe.isTracking, "cancellation resets state")
        _ = event(1)
        swipe.reset()
        expect(event(2, 1) == .pass, "tap recovery discards an unfinished gesture")

        var boundary = SpaceBoundaryState()
        let spaces: [UInt64] = [10, 20, 30]
        func target(_ direction: SpaceDirection, current: UInt64 = 20, now: Double = 1, display: String = "main",
                    topology: [UInt64]? = nil) -> UInt64? {
            boundary.target(direction: direction, display: display, current: current, spaces: topology ?? spaces, now: now)
        }
        expect(target(.previous, current: 10) == nil, "first Space cannot move left")
        expect(target(.next, current: 30) == nil, "last Space cannot move right")
        expect(target(.next) == 30, "neighbor selected")
        boundary.record(target: 30, display: "main", spaces: spaces, now: 1)
        expect(target(.next) == nil, "rapid repeat respects pending destination")
        expect(target(.previous) == 20, "rapid reversal uses pending destination")
        expect(target(.next, display: "external") == 30, "display predictions are isolated")
        expect(target(.next, now: 2) == 30, "failed or missing notifications cannot stick a prediction")
        expect(target(.next, topology: [10, 20, 40]) == 40, "topology changes invalidate prediction")
        boundary.reset()
        expect(target(.previous) == 10, "Space change notification resets to live state")
        expect(target(.next, current: 99) == nil, "unknown current Space cannot post a gesture")
        expect(target(.next, topology: []) == nil, "empty display cannot post a gesture")
        expect(SpaceTransitionSpeed.instant.rampDuration == nil, "instant posts without a ramp")
        expect(SpaceTransitionSpeed.quick.rampDuration == .milliseconds(30), "quick ramp duration")
        expect(SpaceTransitionSpeed.smooth.rampDuration == .milliseconds(60), "smooth ramp duration")
        let fields = SpaceGesture.fields(
            phase: .changed, direction: .next, augmented: false, timestamp: 1, progress: 0.2, velocity: 65)
        expect(fields.contains(.init(raw: 124, value: .double(0.2))), "ramp sets explicit progress")
        expect(fields.contains(.init(raw: 129, value: .double(65))), "ramp sets explicit velocity")
        print("Spaces gesture and boundary checks passed")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }
}
