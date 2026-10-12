import Foundation

enum KeystrokeKind: Sendable {
    case character
    case space
    case delete
    case enter
}

enum KeystrokePhase: Sendable {
    case down
    case up
}

enum InputSoundEvent: Sendable {
    case key(KeystrokeKind, KeystrokePhase)
    case mouse(MouseClickKind, KeystrokePhase)
}

enum MouseClickKind: Sendable {
    case primary
    case secondary
    case other
}
