import AppKit
import SwiftUI

@main
@MainActor
struct PaletteSurfaceTests {
    static func main() {
        for size in InterfaceSize.allCases {
            let metrics = size.metrics
            let anchor = CGPoint(x: -320, y: 900)
            let favorites = LauncherBody.grid(count: 8, columns: 4)
            let launcher = PaletteSurface(mode: .launcher, collapsed: false, launcher: favorites, metrics: metrics)
            let compact = PaletteSurface(mode: .launcher, collapsed: true, launcher: favorites, metrics: metrics)
            let ai = PaletteSurface(mode: .ai, collapsed: false, launcher: favorites, metrics: metrics)
            precondition(launcher.width < ai.width)
            precondition(launcher.frame(at: anchor).midX == ai.frame(at: anchor).midX)
            precondition(launcher.frame(at: anchor).maxY == compact.frame(at: anchor).maxY)
            precondition(launcher.anchor(of: launcher.frame(at: anchor)) == anchor)
            precondition(ai.anchor(of: ai.frame(at: anchor)) == anchor)
            precondition(compact.height == metrics.size.headerHeight)
            precondition(compact.cardTop == nil)
            precondition(launcher.cardGap == metrics.spacing.md)
            let rect = CGRect(origin: .zero, size: CGSize(width: launcher.width, height: launcher.height))
            let path = launcher.shape.path(in: rect)
            precondition(path.contains(CGPoint(x: rect.midX, y: launcher.fieldHeight / 2)))
            precondition(!path.contains(CGPoint(x: rect.midX, y: launcher.headerExtent + launcher.cardGap / 2)))
            precondition(path.contains(CGPoint(x: rect.midX, y: launcher.cardTop! + launcher.radius)))

            let inset = metrics.spacing.md * 2
            let twoRows = metrics.size.launcherTileHeight * 2 + metrics.spacing.xs
            precondition(launcher.height == launcher.cardTop! + inset + twoRows)
            let one = surface(.list(count: 1), metrics)
            let none = surface(.list(count: 0), metrics)
            let many = surface(.list(count: 200), metrics)
            let crowded = surface(.grid(count: 40, columns: 4), metrics)
            precondition(one.height == one.cardTop! + inset + metrics.size.launcherRowHeight)
            precondition(none.height == one.height)
            precondition(many.height == surface(.list(count: Theme.Size.launcherVisibleRows), metrics).height)
            precondition(crowded.height == surface(.grid(count: 12, columns: 4), metrics).height)
            precondition(surface(.grid(count: 5, columns: 4), metrics).height == launcher.height)
            for other in [one, none, many, crowded] {
                precondition(other.frame(at: anchor).maxY == launcher.frame(at: anchor).maxY)
                precondition(other.frame(at: anchor).midX == launcher.frame(at: anchor).midX)
                precondition(other.expandedHeight == launcher.expandedHeight)
                precondition(other.height <= other.expandedHeight)
            }
            precondition(max(many.height, crowded.height) == launcher.expandedHeight)
            precondition(ai.height == metrics.size.panelHeight)
        }
        print("Palette sizing, content-aware launcher height and separated surfaces passed")
    }

    private static func surface(_ body: LauncherBody, _ metrics: InterfaceMetrics) -> PaletteSurface {
        PaletteSurface(mode: .launcher, collapsed: false, launcher: body, metrics: metrics)
    }
}
