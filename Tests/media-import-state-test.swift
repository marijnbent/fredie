import AppKit
import SwiftUI

@MainActor
final class FeatureFlag { var enabled = false }

@MainActor
final class ScanGate {
    var calls = 0
    var pending: CheckedContinuation<[MediaClip], Never>?
    func run() async -> [MediaClip] {
        calls += 1
        return await withCheckedContinuation { pending = $0 }
    }
    func finish(_ clips: [MediaClip]) {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: clips)
    }
}

@main
@MainActor
struct MediaImportStateTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "ollie.media-state.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = ScanGate()
        let flag = FeatureFlag()
        let state = MediaImportState(isEnabled: { flag.enabled },
            settingsStore: MediaImportSettingsStore(defaults: defaults),
            ledger: ImportLedger(fileURL: directory.appendingPathComponent("ledger.json")),
            scan: { _, _ in await gate.run() })
        let source = MediaSource(id: "fixture", name: "Fixture", kind: .folder(directory))
        let clip = MediaClip(id: "clip", origin: .file(directory.appendingPathComponent("clip.mov")),
            originalName: "clip.mov", recordingDate: Date(), duration: 1, fileSize: 1,
            fingerprint: "fixture", status: .ready)
        state.load(source)
        state.handleDetectedSource(source)
        state.startImport()
        precondition(!state.isScanning && !state.isImporting && gate.calls == 0)
        precondition(!state.prepareOriginalDeletion())
        flag.enabled = true
        state.load(source)
        for _ in 0..<100 where gate.calls == 0 { await Task.yield() }
        precondition(gate.calls == 1)
        flag.enabled = false
        state.stop()
        gate.finish([clip])
        for _ in 0..<100 { await Task.yield() }
        precondition(state.clips.isEmpty && !state.isScanning)
        state.load(source)
        state.startImport()
        precondition(gate.calls == 1 && !state.isImporting)
        flag.enabled = true
        state.load(source)
        for _ in 0..<100 where gate.calls == 1 { await Task.yield() }
        precondition(gate.calls == 2)
        gate.finish([clip])
        for _ in 0..<100 where state.isScanning { await Task.yield() }
        precondition(state.clips.map(\.id) == ["clip"])
        flag.enabled = false
        state.stop()
        await state.finishStopping()
        print("Disabled media actions, late scan cancellation and re-enable passed")
    }
}
