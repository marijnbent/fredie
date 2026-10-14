import SwiftUI

struct NetworkMenuSection: View {
    let network: NetworkCoordinator
    let open: () -> Void
    @State private var expanded = false
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "network").frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Network").font(.system(size: 12, weight: .medium))
                        Text(network.status).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("↓ \(NetworkCoordinator.bytes(network.rate.received))/s")
                        Text("↑ \(NetworkCoordinator.bytes(network.rate.sent))/s").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10)).monospacedDigit()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.barControl))
                .background(hovered ? Theme.Colors.rowHover : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.barControl))
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .accessibilityLabel("Network, \(network.status)")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                ForEach(network.apps.prefix(4)) { usage in
                    HStack(spacing: 8) {
                        Image(nsImage: network.icon(usage.app)).resizable().frame(width: 16, height: 16)
                        Text(usage.app.name).lineLimit(1)
                        Spacer()
                        Text(NetworkCoordinator.bytes(usage.traffic.total)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                }
                Button("All usage…", action: open).buttonStyle(.link).font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, expanded ? 8 : 0)
    }
}
