import Foundation

final class WindowDiscoveryProfiler {
    private let diagnostics = SwitcherDiagnostics()
    private var measurements: [String: Double] = [:]
    private var isRecording = false

    func beginSnapshot() {
        isRecording = diagnostics.isEnabled
        guard isRecording else {
            return
        }
        measurements.removeAll(keepingCapacity: true)
    }

    func measure<T>(_ name: String, _ work: () -> T) -> T {
        guard isRecording else {
            return work()
        }
        let start = ContinuousClock.now
        let result = work()
        measurements[name] = SwitcherDiagnostics.elapsedMilliseconds(since: start)
        return result
    }

    func finishSnapshot(itemCount: Int) {
        guard isRecording else {
            return
        }
        let total = measurements["snapshot"] ?? 0
        diagnostics.benchmark(
            "windowDiscovery.snapshot",
            durationMilliseconds: total,
            details: "items=\(itemCount) context_ms=\(number("snapshot.context")) registry_ms=\(number("snapshot.cachedRegistry")) prune_ms=\(number("snapshot.pruneActivationState")) activation_index_ms=\(number("snapshot.activationRecordIndex")) ranking_ms=\(number("snapshot.ranking")) sort_ms=\(number("snapshot.sort"))"
        )
    }

    private func number(_ name: String) -> String {
        String(format: "%.2f", measurements[name] ?? 0)
    }
}
