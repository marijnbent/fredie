import Foundation

enum PaletteTabAction: Equatable {
    /// The typed text rides along, because both ends narrow their own list by the same query.
    case carryQuery(PaletteMode)
    /// The typed text is the question, so chat opens on the answer rather than an empty composer.
    case ask

    static func resolve(mode: PaletteMode, aiEnabled: Bool) -> Self {
        switch mode {
        case .launcher where aiEnabled: .ask
        default: .carryQuery(.launcher)
        }
    }
}
