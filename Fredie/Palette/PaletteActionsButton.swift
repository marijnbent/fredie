import SwiftUI

extension EnvironmentValues {
    @Entry var paletteActionsAvailable = false
    @Entry var paletteActionsArrowAvailable = false
}

struct PaletteActionsButton: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.paletteActionsAvailable) private var available
    @Environment(\.paletteActionsArrowAvailable) private var arrowAvailable
    let action: () -> Void

    var body: some View {
        if available {
            Button(action: action) {
                HStack(spacing: metrics.scaled(5)) {
                    Text("Actions")
                    KeyCapChip(text: "⌘K", style: .outline)
                    if arrowAvailable {
                        Image(systemName: "chevron.right").font(.system(size: metrics.scaled(9)))
                    }
                }
                .font(.system(size: metrics.scaled(11)))
                .padding(.horizontal, metrics.scaled(6))
                .padding(.vertical, metrics.scaled(4))
                .background(Theme.Colors.controlSurface, in: RoundedRectangle(cornerRadius: metrics.scaled(5)))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Actions")
            .help(arrowAvailable ? "Actions (⌘K or → at the end of search)" : "Actions (⌘K)")
        }
    }
}
