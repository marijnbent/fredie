import Foundation

enum DoubleTapModifier: String, CaseIterable, Codable, Sendable {
    case control
    case option
    case shift
    case command

    var glyph: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    var keycaps: [String] { [glyph, glyph] }
}
