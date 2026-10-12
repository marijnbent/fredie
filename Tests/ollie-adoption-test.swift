import Foundation
import SQLite3

enum Paster { static let fredieEventTag: Int64 = 0x465245444945 }
extension Notification.Name { static let bufferDidWritePasteboard = Notification.Name("fixtureOwnPaste") }

@main @MainActor struct OllieAdoptionTests {
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ollie-adoption-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("clippie")
        let target = root.appendingPathComponent("Clipboard")
        let storage = ClipboardStorage(storageDirectory: source)
        let item = ClipboardItem.text("keep original", timestamp: Date())
        try storage.writeHistory([item])
        let original = try Data(contentsOf: source.appendingPathComponent("history.json"))
        try LegacyDataCopy.copy(source: source, destination: target, kind: "clipboard")
        precondition(tryData(source.appendingPathComponent("history.json")) == original)
        precondition(tryData(target.appendingPathComponent("history.json")) == original)
        expectFailure { try LegacyDataCopy.copy(source: source, destination: target, kind: "clipboard") }
        precondition(tryData(target.appendingPathComponent("history.json")) == original)
        let emptyTarget = root.appendingPathComponent("EmptyClipboard")
        let emptyStorage = ClipboardStorage(storageDirectory: emptyTarget)
        try emptyStorage.writeHistory([])
        try Data("orphan".utf8).write(to: emptyTarget.appendingPathComponent("images/orphan.png"))
        expectFailure { try LegacyDataCopy.copy(source: source, destination: emptyTarget, kind: "clipboard") }
        precondition(fm.fileExists(atPath: emptyTarget.appendingPathComponent("images/orphan.png").path))
        let linked = root.appendingPathComponent("linked")
        try fm.createSymbolicLink(at: linked, withDestinationURL: source)
        expectFailure { try LegacyDataCopy.copy(source: linked, destination: root.appendingPathComponent("Rejected"), kind: "clipboard") }

        let talkie = root.appendingPathComponent("Talkie")
        let audio = talkie.appendingPathComponent("HistoryAudio")
        try fm.createDirectory(at: audio, withIntermediateDirectories: true)
        let recording = audio.appendingPathComponent("sample.wav")
        try Data([1, 2, 3, 4]).write(to: recording)
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: "fixture", rawRecordingFileURL: recording)
        let history = TranscriptHistoryStore(fileURL: talkie.appendingPathComponent("transcript-history.json"))
        try history.saveEntries([entry])
        let dictation = root.appendingPathComponent("Dictation")
        try LegacyDataCopy.copy(source: talkie, destination: dictation, kind: "dictation")
        let imported = try TranscriptHistoryStore(fileURL: dictation.appendingPathComponent("transcript-history.json")).loadEntries()
        precondition(imported.count == 1 && imported[0].text == "fixture")
        guard let copy = imported.first?.rawRecordingFileURL else { fatalError("Recording missing") }
        precondition(copy.deletingLastPathComponent().path == dictation.appendingPathComponent("Recordings").path)
        precondition(tryData(copy) == tryData(recording))
        let permissions = try fm.attributesOfItem(atPath: copy.path)[.posixPermissions] as? Int
        precondition(permissions == 0o600)

        let net = root.appendingPathComponent("Nettie")
        try fm.createDirectory(at: net, withIntermediateDirectories: true)
        var database: OpaquePointer?
        precondition(sqlite3_open(net.appendingPathComponent("usage.sqlite").path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        precondition(sqlite3_exec(database, "PRAGMA journal_mode=WAL; CREATE TABLE fixture(value); INSERT INTO fixture VALUES(42);", nil, nil, nil) == SQLITE_OK)
        let network = root.appendingPathComponent("Network")
        try LegacyDataCopy.copy(source: net, destination: network, kind: "network")
        var snapshot: OpaquePointer?
        precondition(sqlite3_open(network.appendingPathComponent("usage.sqlite").path, &snapshot) == SQLITE_OK)
        defer { sqlite3_close(snapshot) }
        var statement: OpaquePointer?
        precondition(sqlite3_prepare_v2(snapshot, "SELECT value FROM fixture", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        precondition(sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) == 42)
        print("PASS: original preservation, occupied destinations, orphan payloads, symlinks, rewritten private recordings, live WAL snapshot")
    }

    private static func expectFailure(_ action: () throws -> Void) {
        do { try action(); fatalError("Unsafe import accepted") } catch { }
    }

    private static func tryData(_ url: URL) -> Data? { try? Data(contentsOf: url) }
}
