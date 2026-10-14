import Foundation

enum OverlayPosition: String, Codable, CaseIterable, Identifiable {
    case top
    case bottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }
}

enum DictationHistoryLimit: Int, Codable, CaseIterable, Identifiable {
    case none = 0
    case ten = 10
    case hundred = 100

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .ten: "10"
        case .hundred: "100"
        }
    }
}
