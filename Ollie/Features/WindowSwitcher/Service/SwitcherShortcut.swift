import AppKit
import Carbon

struct SwitcherShortcut: Codable, Hashable {
    let keyCode: UInt16
    let modifiers: UInt64
    let name: String

    func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        let sanitized = modifiers.intersection(relevant)
        return self.keyCode == keyCode && UInt64(sanitized.rawValue) == self.modifiers
    }

    var defaultWindowScope: WindowScope? {
        switch (keyCode, modifiers) {
        case (UInt16(kVK_ANSI_Grave), UInt64(NSEvent.ModifierFlags.command.rawValue)),
             (UInt16(kVK_ANSI_Grave), UInt64(NSEvent.ModifierFlags.command.union(.shift).rawValue)):
            return .activeApp
        default:
            return nil
        }
    }

    static let commandTab = SwitcherShortcut(
        keyCode: UInt16(kVK_Tab),
        modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue),
        name: "Command-Tab"
    )

    static let commandBacktick = SwitcherShortcut(
        keyCode: UInt16(kVK_ANSI_Grave),
        modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue),
        name: "Command-Backtick (`)"
    )

    static let reverseCommandBacktick = SwitcherShortcut(
        keyCode: UInt16(kVK_ANSI_Grave),
        modifiers: UInt64((NSEvent.ModifierFlags.command.union(.shift)).rawValue),
        name: "Shift-Command-Backtick (`)"
    )

    static let supportedActivators: [SwitcherShortcut] = [
        .commandTab,
        .commandBacktick,
    ]
}

extension Array where Element == SwitcherShortcut {
    static let defaultActivators: [SwitcherShortcut] = SwitcherShortcut.supportedActivators
}
