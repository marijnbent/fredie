import CoreGraphics

enum PaletteDensity: String, CaseIterable, Identifiable, Sendable {
    case compact
    case comfortable

    var id: String { rawValue }
    var title: String { self == .compact ? "Compact" : "Comfortable" }
    var searchHeight: CGFloat { self == .compact ? Theme.Size.compactSearchHeight : Theme.Size.comfortableSearchHeight }
    var launcherRowHeight: CGFloat { self == .compact ? Theme.Size.compactLauncherRowHeight : Theme.Size.comfortablePaletteRowHeight }
    var clipboardRowHeight: CGFloat { self == .compact ? Theme.Size.compactClipboardRowHeight : Theme.Size.comfortablePaletteRowHeight }
    var gap: CGFloat { self == .compact ? Theme.Size.compactPaletteGap : Theme.Size.comfortablePaletteGap }
}

/// How large the palette and its floating siblings render; an unset key reads as `.standard`.
enum InterfaceSize: String, CaseIterable, Identifiable, Sendable {
    case standard
    case large
    case larger

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Default"
        case .large: "Large"
        case .larger: "Larger"
        }
    }

    var scale: CGFloat {
        switch self {
        case .standard: 1
        case .large: 1.1
        case .larger: 1.2
        }
    }

    var metrics: InterfaceMetrics { InterfaceMetrics(scale: scale) }
}
