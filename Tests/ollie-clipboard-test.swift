import AppKit
import Foundation

enum Paster { static let fredieEventTag: Int64 = 0x465245444945 }
extension Notification.Name {
    static let bufferDidWritePasteboard = Notification.Name("bufferDidWritePasteboard")
}

@main
@MainActor
struct OllieClipboardTests {
    private static var failures = 0

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(storageDirectory: directory)
        await store.load()
        let text = String(repeating: "large text ", count: 120_000) + "last-needle"
        let capture = ClipboardCapture(payload: .text(text), sourceApp: "Fixture", sourceBundleIdentifier: nil)
        let captured = try ClipboardWatcher.process(capture, previous: nil, storage: store.storage)!
        check("large text remains file backed", captured.0.textFilename != nil && captured.0.textContent!.count == 500)
        check("identical captures deduplicate", try ClipboardWatcher.process(capture, previous: captured.1, storage: store.storage) == nil)
        store.add(captured.0)
        let inline = ClipboardItem.text("inline", timestamp: Date())
        store.add(inline)
        store.delete(inline)
        check("queued snapshots flush", await store.flush())
        let reopened = ClipboardStore(storageDirectory: directory)
        await reopened.load()
        check("latest snapshot survives reopen", reopened.items == [captured.0])
        check("full text paste preserves every byte", try await reopened.storage.loadActionText(for: captured.0) == text)
        check("search sees beyond preview", reopened.storage.search(reopened.items, normalizedQuery: "last-needle")?.matches.count == 1)
        reopened.delete(captured.0)
        check("delete persists", await reopened.flush())
        check("unreferenced payload removed after commit", !FileManager.default.fileExists(atPath: directory.appendingPathComponent("texts").appendingPathComponent(captured.0.textFilename!).path))

        let outside = directory.appendingPathComponent("outside.txt")
        try Data("keep".utf8).write(to: outside)
        let texts = directory.appendingPathComponent("texts")
        try FileManager.default.createSymbolicLink(at: texts.appendingPathComponent("escape.txt"), withDestinationURL: outside)
        check("path traversal rejected", (try? ClipboardStorage.contentURL("../outside.txt", in: texts)) == nil)
        check("symlink escape rejected", (try? ClipboardStorage.contentURL("escape.txt", in: texts)) == nil)

        let history = directory.appendingPathComponent("history.json")
        try FileManager.default.removeItem(at: history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        reopened.add(.text("retry me", timestamp: Date()))
        check("failed save is visible", !(await reopened.flush()) && reopened.error != nil)
        try FileManager.default.removeItem(at: history)
        check("save retry recovers pending data", await reopened.flush())
        check("retry saved exact snapshot", try reopened.storage.readHistory() == reopened.items)

        let damaged = Data("damaged history".utf8)
        try damaged.write(to: history)
        let unreadable = ClipboardStore(storageDirectory: directory)
        await unreadable.load()
        unreadable.add(.text("must not replace", timestamp: Date()))
        let didFlushDamaged = await unreadable.flush()
        check("failed load cannot overwrite original", try !didFlushDamaged && Data(contentsOf: history) == damaged)

        var tracker = PasteboardChangeTracker(currentChangeCount: 4)
        tracker.recordSelfWrite(changeCount: 5)
        check("own pasteboard write ignored", !tracker.shouldCapture(changeCount: 5))
        check("next external copy captured", tracker.shouldCapture(changeCount: 6))
        tracker.reset(changeCount: 9)
        check("resume does not capture paused content", !tracker.shouldCapture(changeCount: 9))
        try snippets()
        print(failures == 0 ? "Clipboard integration passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func snippets() throws {
        let name = "ollie.clipboard-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SnippetStore(defaults: defaults)
        try store.saveSnippet(title: "", trigger: ":addr", content: "Address")
        try store.saveSnippet(title: "", trigger: "address", content: "Long Address")
        check("exact trigger outranks longer prefix", store.expansionMatches(for: "addr").first?.trigger == "addr")
        do {
            try store.saveSnippet(title: "", trigger: "addr", content: "duplicate")
            check("duplicate triggers rejected", false)
        } catch SnippetStoreError.duplicateTrigger { }
        let reopened = SnippetStore(defaults: defaults)
        check("snippet text persists", reopened.snippets.count == 2 && reopened.exactTriggerMatch(for: "addr")?.content == "Address")
        let damaged = Data("damaged snippets".utf8)
        defaults.set(damaged, forKey: "savedSnippets")
        let unreadable = SnippetStore(defaults: defaults)
        do {
            try unreadable.saveSnippet(title: "", trigger: "new", content: "must not replace")
            check("unreadable snippets reject edits", false)
        } catch SnippetStoreError.unreadableHistory { }
        check("unreadable snippets retained", defaults.data(forKey: "savedSnippets") == damaged)
    }

    private static func check(_ name: String, _ value: Bool) {
        if !value { failures += 1; print("FAIL: \(name)") }
    }
}
