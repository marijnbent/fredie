import Foundation

struct SpaceSwipeState {
    enum Action: Equatable {
        case pass, suppress, switchSpace(SpaceDirection), finish
    }

    private(set) var isTracking = false
    private var fired = false
    private var posted = false

    mutating func reset() {
        isTracking = false
        fired = false
        posted = false
    }

    mutating func didPost(_ posted: Bool) {
        self.posted = posted
    }

    mutating func handle(phase: Int64, progress: Double, velocity: Double, overlayActive: Bool) -> Action {
        switch phase {
        case 1:
            reset()
            guard !overlayActive else { return .pass }
            isTracking = true
            return .suppress
        case 2, 4:
            guard isTracking else { return .pass }
            if !fired {
                let movement = phase == 2 ? progress : velocity
                if movement.isFinite, movement != 0 {
                    fired = true
                    return .switchSpace(movement > 0 ? .next : .previous)
                }
            }
            return phase == 4 ? finish() : .suppress
        case 8:
            guard isTracking else { return .pass }
            reset()
            return .suppress
        default:
            return isTracking ? .suppress : .pass
        }
    }

    mutating func finish() -> Action {
        let result: Action = posted ? .finish : (fired ? .suppress : .pass)
        reset()
        return result
    }
}
