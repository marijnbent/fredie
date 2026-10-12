import AppKit
import SwiftUI

struct MediaImportView: View {
    @Bindable var state: MediaImportState
    @Bindable var settings: MediaImportSettingsStore
    let onChooseSource: () -> Void
    let onOpenSettings: () -> Void
    let onDeleteOriginals: () -> Void
    let onError: (String) async -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
        .task(id: state.alertMessage) {
            guard let message = state.alertMessage else { return }
            await onError(message)
            if state.alertMessage == message { state.alertMessage = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.source?.name ?? "No camera connected")
                    .font(.title2.weight(.semibold))
                if state.clips.isEmpty {
                    Text(state.isScanning ? "Finding videos…" : "Connect a camera or SD card, or choose a folder.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(state.clips.count) videos · \(ByteCountFormatter.string(fromByteCount: state.totalSize, countStyle: .file))")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Choose Folder…", action: onChooseSource)
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var content: some View {
        if state.isScanning {
            VStack(spacing: 12) {
                if state.totalScanFileCount > 0 {
                    ProgressView(value: Double(state.scannedFileCount), total: Double(state.totalScanFileCount))
                        .frame(width: 240)
                    Text("Reading video \(state.scannedFileCount) of \(state.totalScanFileCount)…")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Finding videos…")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        } else if state.clips.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 46))
                    .foregroundStyle(.secondary)
                Text("No videos found")
                    .font(.title3.weight(.medium))
                Button("Choose Source Folder…", action: onChooseSource)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Button("Select All") { state.selectAllReady() }
                        .buttonStyle(.link)
                    Button("Select None") { state.selectNone() }
                        .buttonStyle(.link)
                    Spacer()
                    Text("\(state.selectedCount) selected")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.clips) { clip in
                            ClipRow(
                                clip: clip,
                                thumbnails: state.thumbnails,
                                progress: state.importProgress[clip.id] ?? 0,
                                isSelected: state.selectedClipIDs.contains(clip.id),
                                onToggle: { state.toggleSelection(for: clip.id) }
                            )
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !state.isImporting,
               state.completionMessage != nil || state.deletableOriginalCount > 0 {
                HStack {
                    if let message = state.completionMessage {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state.deletableOriginalCount > 0 {
                        Button {
                            onDeleteOriginals()
                        } label: {
                            Label("Delete Originals…", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)

                    }
                    Button {
                        state.openDestinationFolder()
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("Destination")
                    Picker("", selection: $state.selectedDestinationID) {
                        if settings.availableLocations.isEmpty {
                            Text("No connected preferred location").tag(UUID?.none)
                        }
                        ForEach(settings.availableLocations, id: \.location.id) { item in
                            Text(item.location.name).tag(Optional(item.location.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(state.isImporting)

                    Button(action: onOpenSettings) {
                        Label("Manage…", systemImage: "gearshape")
                    }
                    .disabled(state.isImporting)
                }

                Spacer(minLength: 40)

                if state.isImporting {
                    Button {
                        state.cancelImport()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                } else {
                    Button {
                        state.startImport()
                    } label: {
                        Label("Import Selected", systemImage: "arrow.down.to.line.compact")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.selectedCount == 0 || state.selectedDestinationURL == nil)
                }
            }

            if state.isImporting {
                HStack {
                    ProgressView(
                        value: state.overallImportProgress,
                        total: 1
                    )
                    Text("\(Int(state.overallImportProgress * 100))% · \(state.completedCount) of \(state.totalImportCount) finished · \(state.activeImportCount) active")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(.bar)
    }
}

private struct ClipRow: View {
    let clip: MediaClip
    let thumbnails: ThumbnailStore
    let progress: Double
    @State private var thumbnailImage: NSImage?
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(clip.status.isSelectionDisabled)

            thumbnail

            VStack(alignment: .leading, spacing: 5) {
                Text(clip.originalName)
                    .lineLimit(1)
                    .fontWeight(.medium)
                HStack(spacing: 10) {
                    Text(Self.dateFormatter.string(from: clip.recordingDate))
                    Text(Self.duration(clip.duration))
                    Text(ByteCountFormatter.string(fromByteCount: clip.fileSize, countStyle: .file))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
            statusView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .task(id: clip.fingerprint) {
            let image = await thumbnails.image(for: clip)
            guard !Task.isCancelled else { return }
            thumbnailImage = image
        }
        .onDisappear { thumbnailImage = nil }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = thumbnailImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 84, height: 52)
                .overlay(Image(systemName: "video").foregroundStyle(.secondary))
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch clip.status {
        case .ready:
            EmptyView()
        case .importing:
            VStack(alignment: .trailing, spacing: 4) {
                Text(progress >= 0.95 ? "Checking…" : "\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                ProgressView(value: progress)
                    .frame(width: 80)
            }
        case .imported:
            Label("Imported", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed(let message):
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .help(message)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func duration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private extension ImportStatus {
    var isSelectionDisabled: Bool {
        switch self {
        case .importing, .imported:
            true
        case .ready, .failed:
            false
        }
    }
}
