import SwiftUI

enum LauncherBody: Equatable {
    case list(count: Int)
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

    init(mode: PaletteMode, collapsed: Bool, launcher: LauncherBody, metrics: InterfaceMetrics, density: PaletteDensity = .compact) {
        let size = metrics.size
        slotWidth = size.panelWidth
        detached = mode == .launcher || mode == .clipboard
        fieldHeight = detached ? metrics.scaled(density.searchHeight) : size.headerHeight
        radius = detached ? metrics.scaled(Theme.Size.floatingRadius) : metrics.radius.panel
        if detached {
            let cardTop = fieldHeight + metrics.scaled(density.gap)
            width = metrics.scaled(mode == .clipboard ? Theme.Size.clipboardWidth : Theme.Size.launcherWidth)
            fieldTop = 0
            let rowHeight = metrics.scaled(density.launcherRowHeight)
            let inset = metrics.scaled(Theme.Size.paletteCardInset * 2)
            let count: Int
            switch launcher {
            case .list(let value): count = value
            }
            let cardHeight = mode == .clipboard
                ? metrics.scaled(density.clipboardRowHeight) * 10 + inset
                : inset + CGFloat(min(max(count, 1), 10)) * rowHeight
            expandedHeight = cardTop + (mode == .clipboard ? cardHeight : inset + 10 * rowHeight)
            self.cardTop = collapsed ? nil : cardTop
            height = collapsed ? fieldHeight : cardTop + cardHeight
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
            cornerRadius: radius, style: .continuous)
        if let cardTop, rect.height > cardTop {
            path.addRoundedRect(
                in: CGRect(
                    x: rect.minX, y: rect.minY + cardTop, width: rect.width, height: rect.height - cardTop),
                cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        }
        return path
    }
}
