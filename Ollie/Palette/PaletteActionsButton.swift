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
    @State private var hovered = false

    var body: some View {
        if available {
            Button(action: action) {
                HStack(spacing: metrics.scaled(5)) {
                    Text("Actions").foregroundStyle(Theme.Colors.textSecondary)
                    if arrowAvailable {
                        Image(systemName: "chevron.right").font(.system(size: metrics.scaled(9), weight: .medium))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .font(.system(size: metrics.scaled(11)))
                .padding(.horizontal, metrics.scaled(6))
                .frame(height: metrics.scaled(24))
                .contentShape(RoundedRectangle(cornerRadius: metrics.scaled(5)))
                .background(hovered ? Theme.Colors.rowHover : .clear, in: RoundedRectangle(cornerRadius: metrics.scaled(5)))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .onHover { hovered = $0 }
            .accessibilityLabel("Actions")
            .help(arrowAvailable ? "Actions (→ at the end of search)" : "Actions")
        }
    }
}
