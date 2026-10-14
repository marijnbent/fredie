import SwiftUI

struct HUDGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat = Theme.Size.floatingRadius

    var body: some View {
        MaterialView(reduceTransparency: reduceTransparency)
            .overlay(reduceTransparency ? Theme.Colors.hudOpaqueTint : Theme.Colors.hudGlassTint)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.Colors.hudGlassBorder, lineWidth: 1)
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
