import Foundation

enum LauncherTileStyle: String, CaseIterable, Identifiable, Sendable {
    case iconHighlight
    case fullTile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconHighlight: "Icon highlight"
        case .fullTile: "Full tile"
        }
    }
}
