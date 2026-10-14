import Foundation

enum SoundProfile: String, CaseIterable, Sendable {
    case deepThock
    case glassTactile
    case mutedThock
    case creamyLinear
    case speedClick
    case classicTypewriter
    case retroTerminal

    var menuTitle: String {
        switch self {
        case .deepThock:
            "Deep Thock"
        case .glassTactile:
            "Glass Tactile"
        case .mutedThock:
            "Muted Thock"
        case .creamyLinear:
            "Creamy Linear"
        case .speedClick:
            "Speed Click"
        case .classicTypewriter:
            "Classic Typewriter"
        case .retroTerminal:
            "Retro Terminal"
        }
    }
}
