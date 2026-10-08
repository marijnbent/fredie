import AppKit
import SwiftUI

@main
@MainActor
struct PaletteSurfaceTests {
    static func main() {
        for size in InterfaceSize.allCases {
            let metrics = size.metrics
            let anchor = CGPoint(x: -320, y: 900)
            let launcher = PaletteSurface(mode: .launcher, collapsed: false, metrics: metrics)
            let compact = PaletteSurface(mode: .launcher, collapsed: true, metrics: metrics)
            let ai = PaletteSurface(mode: .ai, collapsed: false, metrics: metrics)
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
        }
        print("Palette sizing, mode transitions and separated surfaces passed")
    }
}
