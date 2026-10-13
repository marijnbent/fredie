import AppKit
import SwiftUI

@main
@MainActor
struct PaletteSurfaceTests {
    static func main() {
        for size in InterfaceSize.allCases {
            for density in PaletteDensity.allCases {
                let metrics = size.metrics
                let anchor = CGPoint(x: -320, y: 900)
                func surface(_ mode: PaletteMode, _ count: Int = 8, collapsed: Bool = false) -> PaletteSurface {
                    PaletteSurface(mode: mode, collapsed: collapsed, launcher: .list(count: count), metrics: metrics, density: density)
                }
                let launcher = surface(.launcher)
                let compact = surface(.launcher, collapsed: true)
                let clipboard = surface(.clipboard)
                let ai = surface(.ai)
                precondition(launcher.width < clipboard.width)
                precondition(launcher.frame(at: anchor).midX == clipboard.frame(at: anchor).midX)
                precondition(launcher.frame(at: anchor).maxY == compact.frame(at: anchor).maxY)
                precondition(launcher.anchor(of: launcher.frame(at: anchor)) == anchor)
                precondition(clipboard.anchor(of: clipboard.frame(at: anchor)) == anchor)
                precondition(compact.height == metrics.scaled(density.searchHeight))
                precondition(compact.cardTop == nil)
                precondition(launcher.cardGap == metrics.scaled(density.gap))
                let rect = CGRect(origin: .zero, size: CGSize(width: launcher.width, height: launcher.height))
                let path = launcher.shape.path(in: rect)
                precondition(path.contains(CGPoint(x: rect.midX, y: launcher.fieldHeight / 2)))
                precondition(!path.contains(CGPoint(x: rect.midX, y: launcher.headerExtent + launcher.cardGap / 2)))
                precondition(path.contains(CGPoint(x: rect.midX, y: launcher.cardTop! + launcher.radius)))
                let one = surface(.launcher, 1)
                let none = surface(.launcher, 0)
                let many = surface(.launcher, 200)
                precondition(abs(one.height - one.cardTop! - (metrics.scaled(8) + metrics.scaled(density.launcherRowHeight))) < 0.001)
                precondition(none.height == one.height)
                precondition(many.height == surface(.launcher, 10).height)
                precondition(surface(.clipboard, 0).height == clipboard.height)
                for other in [one, none, many, clipboard] {
                    precondition(other.frame(at: anchor).maxY == launcher.frame(at: anchor).maxY)
                    precondition(other.frame(at: anchor).midX == launcher.frame(at: anchor).midX)
                    precondition(other.height <= other.expandedHeight)
                }
                precondition(many.height == launcher.expandedHeight)
                precondition(ai.height == metrics.size.panelHeight)
            }
        }
        print("Floating surfaces, density, stable anchors and clipboard empty-state sizing passed")
    }
}
