import Foundation
import OSLog

struct SwitcherDiagnostics: Sendable {
    private static let logger = Logger(subsystem: "nl.bentjes.fredie", category: "window-switcher")
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: "switcherDiagnosticsEnabled") }
    func setEnabled(_ enabled: Bool) { UserDefaults.standard.set(enabled, forKey: "switcherDiagnosticsEnabled") }
    func info(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        Self.logger.debug("\(text, privacy: .private)")
    }
    func warning(_ message: @autoclosure () -> String) { info(message()) }
    func error(_ message: @autoclosure () -> String) { info(message()) }

    @discardableResult
    func measure<T>(_ name: @autoclosure () -> String, thresholdMilliseconds: Double = 0, _ work: () -> T) -> T {
        guard isEnabled else {
            return work()
        }

        let start = ContinuousClock.now
        let result = work()
        let milliseconds = Self.milliseconds(from: start.duration(to: .now))

        if milliseconds >= thresholdMilliseconds {
            info("\(name()): \(Self.format(milliseconds)) ms")
        }

        return result
    }

    func benchmark(
        _ name: String,
        since start: ContinuousClock.Instant,
        details: @autoclosure () -> String = ""
    ) {
        benchmark(
            name,
            durationMilliseconds: Self.elapsedMilliseconds(since: start),
            details: details()
        )
    }

    func benchmark(
        _ name: String,
        durationMilliseconds: Double,
        details: @autoclosure () -> String = ""
    ) {
        guard isEnabled else {
            return
        }

        let suffix = details()
        let detailText = suffix.isEmpty ? "" : " \(suffix)"
        info("benchmark.\(name) duration_ms=\(Self.format(durationMilliseconds))\(detailText)")
    }

    func benchmarkEvent(_ name: String, details: @autoclosure () -> String = "") {
        guard isEnabled else {
            return
        }

        let suffix = details()
        let detailText = suffix.isEmpty ? "" : " \(suffix)"
        info("benchmark.\(name)\(detailText)")
    }

    static func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
        milliseconds(from: start.duration(to: .now))
    }


    static func milliseconds(from duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }
    static func format(_ value: Double) -> String { String(format: "%.2f", value) }
}
