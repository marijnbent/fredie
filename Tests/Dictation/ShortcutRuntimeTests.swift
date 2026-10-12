import AppKit
import Foundation
import Carbon

@MainActor
final class ShortcutRuntimeTests {
    private let superCapsLockModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift,
    ]

    func testSuperCapsLockCyclesOncePerPressOnlyWhileRecording() {
        let eventMonitor = FakeEventMonitorPort()
        let runtime = ShortcutRuntime(
            eventMonitor: eventMonitor,
            clock: ManualClock(),
            clickHoldThreshold: 0.2
        )
        var phase = RecordingPhase.idle
        var cycleCount = 0
        runtime.phaseProvider = { phase }
        runtime.onCycleLanguage = { cycleCount += 1 }
        runtime.start()

        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: superCapsLockModifiers
        )
        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: []
        )
        assertEqual(cycleCount, 0)

        phase = .recording
        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: superCapsLockModifiers
        )
        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Command),
            modifiers: superCapsLockModifiers
        )
        assertEqual(cycleCount, 1)

        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: []
        )
        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: superCapsLockModifiers
        )
        assertEqual(cycleCount, 2)

        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: []
        )
        phase = .finalizing
        eventMonitor.sendFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifiers: superCapsLockModifiers
        )
        assertEqual(cycleCount, 2)
    }

    func testCompanionKeyDiscardsRecordingWhileShortcutIsHeldWithoutConsumingKey() {
        let harness = makeCompanionKeyHarness()

        harness.eventMonitor.sendFlagsChanged(
            keyCode: harness.shortcut.key.keyCode,
            modifiers: harness.shortcut.key.modifierFlag
        )
        harness.clock.currentTime = 1
        let wasConsumed = harness.eventMonitor.sendKeyDown(CGKeyCode(kVK_ANSI_Slash))

        assertFalse(wasConsumed)
        assertEqual(harness.receivedActions.value.last, .discard)
    }

    func testFnKeyDownDoesNotDiscardItsOwnQuickPress() {
        let harness = makeCompanionKeyHarness(key: .fn)

        harness.eventMonitor.sendFlagsChanged(
            keyCode: harness.shortcut.key.keyCode,
            modifiers: harness.shortcut.key.modifierFlag
        )
        _ = harness.eventMonitor.sendKeyDown(CGKeyCode(harness.shortcut.key.keyCode))
        harness.clock.currentTime = 0.1
        harness.eventMonitor.sendFlagsChanged(
            keyCode: harness.shortcut.key.keyCode,
            modifiers: []
        )

        assertFalse(harness.receivedActions.value.contains(.discard))
        assertTrue(harness.receivedActions.value.contains(.setLatched(true)))
    }

    private func makeCompanionKeyHarness(key: ShortcutKey = .rightOption) -> (
        runtime: ShortcutRuntime,
        eventMonitor: FakeEventMonitorPort,
        clock: ManualClock,
        shortcut: ShortcutConfig,
        receivedActions: ShortcutActionRecorder
    ) {
        let eventMonitor = FakeEventMonitorPort()
        let clock = ManualClock()
        let shortcut = ShortcutConfig(id: UUID(), key: key, mode: .both)
        let runtime = ShortcutRuntime(
            eventMonitor: eventMonitor,
            clock: clock,
            clickHoldThreshold: 0.2
        )
        var phase = RecordingPhase.idle
        var ownership: RecordingOwnership?
        let receivedActions = ShortcutActionRecorder()
        runtime.phaseProvider = { phase }
        runtime.ownershipProvider = { ownership }
        runtime.onActions = { actions in
            receivedActions.value.append(contentsOf: actions)
            if case .start = actions.first {
                phase = .recording
                ownership = RecordingOwnership(
                    ownerShortcutID: shortcut.id,
                    ownerMode: shortcut.mode,
                    isLatched: false,
                    recordingStartedAt: clock.now(),
                    sessionID: UUID()
                )
            }
        }
        runtime.configure(shortcuts: [shortcut])
        runtime.start()
        return (runtime, eventMonitor, clock, shortcut, receivedActions)
    }
}

private final class ShortcutActionRecorder {
    var value: [ShortcutAction] = []
}
