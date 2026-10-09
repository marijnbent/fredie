import SwiftUI

enum LauncherBody: Equatable {
    case grid(count: Int, columns: Int)
    case list(count: Int)

    func cardHeight(_ metrics: InterfaceMetrics) -> CGFloat {
        let inset = metrics.spacing.md * 2
        switch self {
        case .grid(let count, let columns):
            let rows = Self.visible(
                (max(count, 1) + max(columns, 1) - 1) / max(columns, 1),
                limit: Theme.Size.launcherVisibleTileRows)
            return inset + CGFloat(rows) * metrics.size.launcherTileHeight
                + CGFloat(rows - 1) * metrics.spacing.xs
        case .list(let count):
            let rows = Self.visible(count, limit: Theme.Size.launcherVisibleRows)
            return inset + CGFloat(rows) * metrics.size.launcherRowHeight
        }
    }

    static func tallestCard(_ metrics: InterfaceMetrics) -> CGFloat {
        max(
            LauncherBody.grid(count: Theme.Size.launcherVisibleTileRows, columns: 1).cardHeight(metrics),
            LauncherBody.list(count: Theme.Size.launcherVisibleRows).cardHeight(metrics))
    }

    private static func visible(_ rows: Int, limit: Int) -> Int { min(max(rows, 1), limit) }
}

struct PaletteSurface: Equatable {
    let slotWidth: CGFloat
    let width: CGFloat
    let height: CGFloat
    let expandedHeight: CGFloat
    let fieldTop: CGFloat
    let fieldHeight: CGFloat
    let cardTop: CGFloat?
    let detached: Bool
    let radius: CGFloat

    init(mode: PaletteMode, collapsed: Bool, launcher: LauncherBody, metrics: InterfaceMetrics) {
        let size = metrics.size
        slotWidth = size.panelWidth
        fieldHeight = size.headerHeight
        radius = metrics.radius.panel
        detached = mode == .launcher
        if detached {
            let cardTop = size.headerHeight + metrics.spacing.md
            width = size.launcherWidth
            fieldTop = 0
            expandedHeight = cardTop + LauncherBody.tallestCard(metrics)
            self.cardTop = collapsed ? nil : cardTop
            height = collapsed ? size.headerHeight : cardTop + launcher.cardHeight(metrics)
        } else {
            width = size.panelWidth
            fieldTop = size.headerPadding
            cardTop = nil
            expandedHeight = size.panelHeight
            height = collapsed ? size.compactHeight : expandedHeight
        }
    }

    var headerExtent: CGFloat { fieldTop + fieldHeight }

    var cardGap: CGFloat { cardTop.map { $0 - headerExtent } ?? 0 }

    private var inset: CGFloat { (slotWidth - width) / 2 }

    func frame(at anchor: CGPoint) -> CGRect {
        CGRect(x: anchor.x + inset, y: anchor.y - height, width: width, height: height)
    }

    func anchor(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX - inset, y: frame.maxY)
    }

    var shape: PaletteSurfaceShape {
        PaletteSurfaceShape(
            fieldTop: fieldTop, fieldHeight: fieldHeight, cardTop: cardTop, detached: detached,
            radius: radius)
    }
}

struct PaletteCardMask: ViewModifier {
    @Environment(\.metrics) private var metrics
    let top: CGFloat?

    func body(content: Content) -> some View {
        if let top {
            content.mask {
                VStack(spacing: 0) {
                    Color.clear.frame(height: top)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: metrics.spacing.lg)
                    Color.black
                }
                .ignoresSafeArea()
            }
        } else {
            content
        }
    }
}

struct PaletteSurfaceShape: Shape {
    let fieldTop: CGFloat
    let fieldHeight: CGFloat
    let cardTop: CGFloat?
    let detached: Bool
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        guard detached else {
            return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        }
        var path = Path(
            roundedRect: CGRect(x: rect.minX, y: rect.minY + fieldTop, width: rect.width, height: fieldHeight),
            cornerRadius: fieldHeight / 2, style: .continuous)
        if let cardTop, rect.height > cardTop {
            path.addRoundedRect(
                in: CGRect(
                    x: rect.minX, y: rect.minY + cardTop, width: rect.width, height: rect.height - cardTop),
                cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        }
        return path
    }
}
