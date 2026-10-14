import SwiftUI

/// Native Liquid Glass backdrop for Ollie's borderless panels.
struct GlassEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        NSGlassEffectView()
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {}
}
