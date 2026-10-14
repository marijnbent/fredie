import SwiftUI

struct PaletteBackdrop: View {
    let surface: PaletteSurface

    var body: some View {
        if surface.isLauncherOrClipboard {
            HUDGlassBackground(cornerRadius: surface.radius).allowsHitTesting(false)
        } else {
            Theme.Colors.panelScrim.background(GlassEffectView())
        }
    }
}
