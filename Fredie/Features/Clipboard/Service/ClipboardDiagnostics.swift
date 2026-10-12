import Foundation
import OSLog

struct ClipboardDiagnostics: Sendable {
    private static let logger = Logger(subsystem: "nl.bentjes.fredie", category: "clipboard")
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: "clipboardDiagnosticsEnabled") }

    func event(_ name: String, details: @autoclosure () -> String = "") {
        guard isEnabled else { return }
        let detail = details()
        Self.logger.debug("\(name, privacy: .public) \(detail, privacy: .public)")
    }

    func benchmark(_ name: String, durationMilliseconds: @autoclosure () -> Double, details: @autoclosure () -> String = "") {
        guard isEnabled else { return }
        let duration = durationMilliseconds()
        let detail = details()
        Self.logger.debug("\(name, privacy: .public) \(duration)ms \(detail, privacy: .public)")
    }

    static func format(_ value: Double) -> String { String(format: "%.2f", value) }

    static func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
    }
}
