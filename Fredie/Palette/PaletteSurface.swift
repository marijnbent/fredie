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
    let isLauncherOrClipboard: Bool
    let radius: CGFloat

    init(mode: PaletteMode, collapsed: Bool, launcher: LauncherBody, metrics: InterfaceMetrics, density: PaletteDensity = .compact) {
        let size = metrics.size
        slotWidth = size.panelWidth
        isLauncherOrClipboard = mode == .launcher || mode == .clipboard
        fieldHeight = isLauncherOrClipboard ? metrics.scaled(density.searchHeight) : size.headerHeight
        radius = isLauncherOrClipboard ? metrics.scaled(Theme.Size.floatingRadius) : metrics.radius.panel
        if isLauncherOrClipboard {
            let cardTop = fieldHeight
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

    private var inset: CGFloat { (slotWidth - width) / 2 }

    func frame(at anchor: CGPoint) -> CGRect {
        CGRect(x: anchor.x + inset, y: anchor.y - height, width: width, height: height)
    }

    func anchor(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX - inset, y: frame.maxY)
    }

    var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
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
