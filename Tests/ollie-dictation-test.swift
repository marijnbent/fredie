import AppKit
import Foundation

func assertEqual<T: Equatable>(_ first: T, _ second: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { precondition(first == second, "\(message): \(first) != \(second)", file: file, line: line) }
func assertTrue(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { precondition(value, message, file: file, line: line) }
func assertFalse(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { precondition(!value, message, file: file, line: line) }
func assertNil<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { precondition(value == nil, message, file: file, line: line) }
func testFailure(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) { preconditionFailure(message, file: file, line: line) }
func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw NSError(domain: "test", code: 1) }; return value }

private final class HistoryFixture: TranscriptHistoryPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [TranscriptHistoryEntry] = []
    private var shouldFail = true
    private var writes = 0
    var entries: [TranscriptHistoryEntry] { lock.withLock { saved } }
    var attempts: Int { lock.withLock { writes } }
    func saveEntries(_ entries: [TranscriptHistoryEntry]) throws {
        try lock.withLock {
            writes += 1
            if shouldFail { shouldFail = false; throw CocoaError(.fileWriteOutOfSpace) }
            saved = entries
        }
    }
}

@main @MainActor struct OllieDictationTests {
    static func main() async throws {
        await RecordingRuntimeTests().testReconnectsOnceThenStopsRetryingAndFinalizes()
        await RecordingRuntimeTests().testDoesNotReconnectWhileFinalizing()
        await RecordingRuntimeTests().testProviderErrorIsPreservedWhenConnectionThenDrops()
        await RecordingRuntimeTests().testCancelFromEscWhileFinalizingStopsSessionWithoutFinalizing()
        await RecordingRuntimeTests().testDiscardSilentlyStopsProvisionalRecording()
        await RecordingRuntimeTests().testFinalizeIncludesSavedRawRecordingAndLanguage()
        await RecordingRuntimeTests().testChangingLanguageWhileRecordingReconnectsAndFinalizesWithNewLanguage()
        await RecordingRuntimeTests().testRoutesOneConvertedChunkToRawCaptureAndTranscriptionStream()
        await RecordingRuntimeTests().testCancelDuringPendingCaptureStartCannotOpenAStaleSession()
        await PasteRuntimeTests().testPasteKeepsClipboardByDefaultAfterAutoPaste()
        await PasteRuntimeTests().testPasteRestoresClipboardOnlyAfterConfirmedAutoPaste()
        await PasteRuntimeTests().testEnhancementMissingCredentialsFallsBackToOriginalAndRecordsError()
        await PasteRuntimeTests().testCancellationDuringEnhancementSkipsPasteAndEmitsCancelled()
        await PasteRuntimeTests().testRestoreEnabledKeepsClipboardWhenVerificationCannotPrepare()
        await PasteRuntimeTests().testRestoreEnabledKeepsClipboardWhenVerificationMismatches()
        await PasteRuntimeTests().testRestoreEnabledKeepsClipboardWhenVerificationTimesOut()
        await PasteRuntimeTests().testPasteCommandFailureDoesNotRestoreClipboardEvenWhenEnabled()
        ShortcutRuntimeTests().testSuperCapsLockCyclesOncePerPressOnlyWhileRecording()
        ShortcutRuntimeTests().testCompanionKeyDiscardsRecordingWhileShortcutIsHeldWithoutConsumingKey()
        ShortcutRuntimeTests().testFnKeyDownDoesNotDiscardItsOwnQuickPress()
        await PasteRuntimeTests().testNewCopyAndStopCancelPendingRestoration()
        try await historyPersistence()
        print("PASS: dictation runtime, awaited shutdown, clipboard ownership and history retry scenarios")
    }

    private static func historyPersistence() async throws {
        let storage = HistoryFixture()
        var results: [TranscriptHistoryWriteResult] = []
        let writer = TranscriptHistoryWriter(store: storage) { results.append($0) }
        let entry = TranscriptHistoryEntry(timestamp: Date(), text: "newest")
        writer.submit([entry], revision: 1)
        let result = await writer.flush()
        assertEqual(result?.revision, 1)
        assertNil(result?.errorMessage)
        assertEqual(storage.attempts, 2)
        assertEqual(storage.entries.first?.text, "newest")
        assertTrue(results.first?.errorMessage != nil)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("history.json")
        let original = Data("corrupted history".utf8)
        try original.write(to: file)
        let store = TranscriptHistoryStore(fileURL: file)
        let state = DictationSessionState(historyStore: store, initialHistoryIsPersisted: false)
        state.reportHistoryLoadFailure()
        state.storeTranscriptHistoryEntry(entry, limit: .hundred)
        assertFalse(await state.flushHistory())
        assertEqual(try Data(contentsOf: file), original)
    }
}
