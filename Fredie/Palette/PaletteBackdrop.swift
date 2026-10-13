import SwiftUI

struct PaletteBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let surface: PaletteSurface

    var body: some View {
        if surface.detached {
            VStack(spacing: surface.cardGap) {
                glass.frame(height: surface.fieldHeight)
                if surface.cardTop != nil {
                    glass.frame(maxHeight: .infinity)
                }
            }
            .allowsHitTesting(false)
        } else {
            Theme.Colors.panelScrim.background(GlassEffectView())
        }
    }

    private var glass: some View {
        MaterialView(reduceTransparency: reduceTransparency)
            .overlay(reduceTransparency ? Theme.Colors.paletteOpaqueTint : Theme.Colors.paletteGlassTint)
            .clipShape(RoundedRectangle(cornerRadius: surface.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: surface.radius, style: .continuous)
                    .strokeBorder(Theme.Colors.paletteGlassBorder, lineWidth: 1)
            }
    }

    private struct MaterialView: NSViewRepresentable {
        let reduceTransparency: Bool

        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.blendingMode = .withinWindow
            view.state = .active
            view.material = reduceTransparency ? .windowBackground : .hudWindow
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {
            view.material = reduceTransparency ? .windowBackground : .hudWindow
        }
    }
}
