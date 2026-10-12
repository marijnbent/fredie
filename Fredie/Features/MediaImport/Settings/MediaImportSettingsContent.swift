import AppKit
import SwiftUI

struct MediaImportSettingsContent: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(MediaImportCoordinator.self) private var mediaImport
    @Bindable var settings: MediaImportSettingsStore
    let ffmpeg: FFmpegService
    let onLocationsChanged: () -> Void
    let onError: (String) -> Void

    var body: some View {
        @Bindable var appSettings = appSettings
        Form {
            Section {
                Toggle("Media Import", isOn: $appSettings.mediaImportEnabled)
                LegacyAppNotice(app: .mediaImport)
                Button("Open Importer") { mediaImport.show() }
                    .disabled(!appSettings.mediaImportEnabled)
            }
            Section("Preferred Locations") {
                if settings.preferredLocations.isEmpty {
                    Text("Add one or more folders on your external storage.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(settings.preferredLocations.enumerated()), id: \.element.id) { index, location in
                        locationRow(location, index: index)
                    }
                }
                HStack {
                    Button("Add Location…", action: addLocation)
                    Spacer()
                    Text("The first connected location is used by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Behavior") {
                Toggle("Open when a camera or SD card is found", isOn: $settings.openOnDetection)
            }

            Section("Conversion") {
                LabeledContent("Output", value: "MP4")
                LabeledContent("FFmpeg") {
                    if let path = ffmpeg.executablePath {
                        Label(path, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Not found", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                Text("Keeps compatible video streams unchanged. It converts unsupported video to high-quality H.264 and audio to AAC.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Folders") {
                Text("Imported files use: Year / Month / Day / Date and time.mp4")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)

    }

    private func locationRow(_ location: PreferredLocation, index: Int) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(location.resolvedURL() == nil ? Color.secondary : Color.green)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                Text(location.resolvedURL()?.path ?? location.lastKnownPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                settings.moveLocation(from: index, to: index - 1)
                onLocationsChanged()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("Move up")

            Button {
                settings.moveLocation(from: index, to: index + 1)
                onLocationsChanged()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == settings.preferredLocations.count - 1)
            .help("Move down")

            Button(role: .destructive) {
                settings.removeLocations(at: IndexSet(integer: index))
                onLocationsChanged()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
    }

    private func addLocation() {
        let panel = NSOpenPanel()
        panel.title = "Add Preferred Location"
        panel.prompt = "Add"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.addPreferredLocation(url)
            onLocationsChanged()
        } catch {
            onError(error.localizedDescription)
        }
    }
}
