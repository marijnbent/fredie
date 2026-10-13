import Foundation

@main struct DiagnosticsTests {
    static func main() async throws {
        let defaults = UserDefaults.standard
        let key = Diagnostics.preferenceKey
        precondition(AppSettingsKey.diagnosticsEnabled.rawValue == key)
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        let clipboard = Diagnostics(category: "clipboard")
        let switcher = Diagnostics(category: "window-switcher")
        precondition(!clipboard.isEnabled && !switcher.isEnabled)
        var evaluated = 0
        func detail() -> String { evaluated += 1; return "test" }
        func duration() -> Double { evaluated += 1; return 1 }
        clipboard.info(detail())
        clipboard.benchmark("test", durationMilliseconds: duration(), details: detail())
        precondition(evaluated == 0)
        var workCount = 0
        let result = switcher.measure(detail()) { workCount += 1; return 42 }
        precondition(result == 42 && workCount == 1 && evaluated == 0)
        switcher.warning("test.warning", details: detail())
        switcher.error("test.error", details: detail())
        precondition(evaluated == 2)
        for enabled in [false, true, false] {
            defaults.set(enabled, forKey: key)
            precondition(clipboard.isEnabled == enabled && switcher.isEnabled == enabled)
            let before = evaluated
            clipboard.info(detail())
            precondition(evaluated == before + (enabled ? 1 : 0))
            let value = Signposts.interval("test") { 9 }
            precondition(value == 9)
            let asyncValue = await Signposts.interval("asyncTest") { @Sendable () async -> Int in 7 }
            precondition(asyncValue == 7)
        }
        print("PASS: shared diagnostic toggle, lazy details, essential errors, and signpost work")
    }
}
