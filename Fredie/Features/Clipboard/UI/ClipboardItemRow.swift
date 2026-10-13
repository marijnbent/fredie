import SwiftUI

struct ClipboardItemRow: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let item: ClipboardItem
    let store: ClipboardStore
    let isSelected: Bool

    @State private var isHovered = false
    @State private var thumbnail: NSImage?
    @State private var sourceAppIcon: NSImage?

    private var backgroundColor: Color {
        if isSelected {
            return Theme.Colors.selection
        } else if isHovered {
            return Theme.Colors.rowHover
        }
        return Color.clear
    }

    private var backgroundCornerRadius: CGFloat {
        5
    }

    var body: some View {
        HStack(spacing: metrics.scaled(8)) {
            if item.type == .image {
                icon
                    .frame(width: 20, height: 20)
            }

            Text(item.previewText)
                .font(.system(size: metrics.scaled(Theme.Size.clipboardListFontSize)))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let sourceAppIcon {
                Image(nsImage: sourceAppIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: metrics.scaled(Theme.Size.clipboardSourceIcon), height: metrics.scaled(Theme.Size.clipboardSourceIcon))
                    .accessibilityLabel(item.sourceApp ?? "Source application")
                    .tooltip(item.sourceApp ?? "Source application")
            }

        }
        .padding(.horizontal, metrics.scaled(8))
        .frame(height: metrics.scaled(settings.paletteDensity.clipboardRowHeight))
        .background(
            backgroundColor,
            in: RoundedRectangle(cornerRadius: backgroundCornerRadius, style: .continuous)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .task(id: item.id) {
            sourceAppIcon = nil
            thumbnail = nil
            if item.sourceBundleIdentifier != nil || item.sourceApp != nil {
                let icon = await store.storage.imageCache.sourceAppIcon(for: item)
                guard !Task.isCancelled else { return }
                sourceAppIcon = icon
            }
            if item.type == .image {
                let image = await store.storage.imageCache.thumbnail(for: item)
                guard !Task.isCancelled else { return }
                thumbnail = image
            }
        }
    }


    @ViewBuilder
    private var icon: some View {
        if item.type == .image {
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 20, height: 20)
            }
        }
    }

}
