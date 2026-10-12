import AVFoundation
import Foundation

@main
@MainActor
struct OllieServiceTests {
    private static var failures = 0

    static func main() async throws {
        try await sounds()
        try network()
        try notifications()
        try await mediaImport()
        check("updates wait for imports", UpdateReadiness.evaluate(UpdateActivity(isImporting: true)) == .importing)
        check("updates wait for recordings", UpdateReadiness.evaluate(UpdateActivity(isRecording: true)) == .recording)
        print(failures == 0 ? "Ollie services passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func sounds() async throws {
        var volumes: [Float] = []
        let engine = SoundEngine { _, volume in volumes.append(volume) }
        engine.play(.character, phase: .down)
        engine.shutdown()
        try await Task.sleep(for: .milliseconds(150))
        check("shutdown discards input queued before sample preparation", volumes.isEmpty)
        engine.preview(profile: .deepThock, volume: 0.5, downVolume: 0.6, upVolume: 0.2)
        try await wait { !volumes.isEmpty }
        engine.volume = 0.9
        try await wait { volumes.count == 2 }
        check("preview retains the requested volumes", abs(volumes[0] - 0.3) < 0.0001 && abs(volumes[1] - 0.1) < 0.0001)
        engine.preview(profile: .deepThock, volume: 1, downVolume: 1, upVolume: 1)
        try await wait { volumes.count == 3 }
        engine.stop()
        try await Task.sleep(for: .milliseconds(150))
        check("stop cancels the pending key release", volumes.count == 3)
        engine.shutdown()
    }

    private static func network() throws {
        var decoder = NetTopDecoder()
        check("partial traffic frame is buffered", try decoder.append(Data(",bytes_in,bytes_out,\nBrowser.123,90".utf8), at: Date()).isEmpty)
        let frames = try decoder.append(Data("00,20,\nApp, with.dots.44,-12,3,\n,bytes_in,bytes_out,\n".utf8), at: Date())
        check("traffic frames preserve process names", frames[0].rows[1].name == "App, with.dots")
        check("negative OS corrections clamp to zero", frames[0].rows[1].traffic == Traffic(sent: 3))
        check("split byte counters reassemble", frames[0].rows[0].traffic.received == 9000)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let app = MonitoredApp(id: "fixture", name: "Fixture", path: "/fixture")
        do {
            let store = try UsageStore(directory: directory)
            try store.record([AppUsage(app: app, traffic: Traffic(received: 101, sent: 51))],
                from: midnight.addingTimeInterval(-1), to: midnight.addingTimeInterval(1), calendar: calendar)
        }
        let store = try UsageStore(directory: directory)
        let days = try store.days(from: midnight.addingTimeInterval(-86400), through: midnight, appID: app.id, calendar: calendar)
        check("history survives reopen and midnight splitting", days.count == 2 && days.reduce(Traffic()) { $0 + $1.traffic } == Traffic(received: 101, sent: 51))
    }

    private static func notifications() throws {
        let name = "ollie-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let topic = "private-fixture-topic"
        var checkpoint = SubscriptionCheckpoint(topics: [topic])
        checkpoint.record("one", timestamp: 100)
        checkpoint.record("one", timestamp: 101)
        checkpoint.record("two", timestamp: 102)
        checkpoint.save(to: defaults)
        let restored = SubscriptionCheckpoint.load(topics: [topic], from: defaults)
        check("reconnect deduplicates messages", restored.recentMessageIDs == ["one", "two"])
        let different = SubscriptionCheckpoint.load(topics: ["different"], from: defaults)
        check("topic changes reset the replay checkpoint", different.recentMessageIDs.isEmpty)
        let raw = defaults.data(forKey: "ollieNotificationCheckpoint")!
        check("checkpoint never persists private topics", !String(decoding: raw, as: UTF8.self).contains(topic))
        let message = NtfyMessage(id: "fixture", event: "message", topic: nil, title: nil,
            message: nil, priority: nil, click: "file:///etc/passwd", actions: nil)
        check("notification links cannot launch local files or app schemes", message.bestURLString == nil)
        let link = NtfyMessage(id: "fixture", event: "message", topic: nil, title: nil,
            message: nil, priority: nil, click: "https://example.com/status", actions: nil)
        check("notification web links remain available", link.bestURLString == "https://example.com/status")
    }

    private static func mediaImport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source")
        let outside = directory.appendingPathComponent("outside.mp4")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: outside)
        let link = source.appendingPathComponent("link.mp4")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let result = OriginalFileDeleter.delete([link], from: source)
        check("original deletion refuses paths through symlinks outside the source", result.deleted.isEmpty && result.failed.count == 1)
        check("outside originals remain intact", try Data(contentsOf: outside) == Data("keep".utf8))
        let operation = ImportProcessOperation()
        operation.cancel()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        do {
            try operation.start(process)
            check("cancellation before launch prevents child creation", false)
        } catch is CancellationError {
            check("cancellation before launch prevents child creation", !process.isRunning)
        }
    }

    private static func wait(_ ready: () -> Bool) async throws {
        for _ in 0..<400 {
            if ready() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(.coderReadCorrupt)
    }

    private static func check(_ label: String, _ passed: Bool) {
        print("\(passed ? "PASS" : "FAIL")  \(label)")
        if !passed { failures += 1 }
    }
}
