import Foundation

enum SpaceTransitionSpeed: String, CaseIterable, Sendable {
    case instant, quick, smooth

    var title: String { rawValue.capitalized }

    var rampDuration: Duration? {
        switch self {
        case .instant: nil
        case .quick: .milliseconds(30)
        case .smooth: .milliseconds(60)
        }
    }
}
