import Foundation

/// The three surfaces stay reachable one way, and chat is skipped when off.
@main
@MainActor
struct PaletteTabTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ actual: PaletteTabAction, _ expected: PaletteTabAction, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func main() {
        expect(
            PaletteTabAction.resolve(mode: .launcher, aiEnabled: true), .ask,
            "launcher submits its query to AI")
        expect(
            PaletteTabAction.resolve(mode: .launcher, aiEnabled: false), .carryQuery(.launcher),
            "launcher stays open when AI is disabled")
        for mode in PaletteMode.allCases where mode != .launcher {
            expect(
                PaletteTabAction.resolve(mode: mode, aiEnabled: true), .carryQuery(.launcher),
                "Tab returns from \(mode) to launcher")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
