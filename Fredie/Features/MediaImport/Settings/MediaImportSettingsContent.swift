import AppKit
import SwiftUI

struct MediaImportSettingsContent: View {
    @Environment(MediaImportCoordinator.self) private var mediaImport
    @Bindable var settings: MediaImportSettingsStore
    let ffmpeg: FFmpegService
    let onLocationsChanged: () -> Void
    let onError: (String) -> Void

    var body: some View {
        Form {
            Section("Import") {
                SettingsRow(title: "Camera and SD cards") {
                    Button("Open Importer") { mediaImport.show() }
                }
                Toggle("Open when a camera or SD card is found", isOn: $settings.openOnDetection)
            }
            Section {
                if settings.preferredLocations.isEmpty {
                    Text("No locations yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(settings.preferredLocations.enumerated()), id: \.element.id) { index, location in
                        locationRow(location, index: index)
                    }
                }
                Button("Add Location…", action: addLocation)
            } header: {
                Text("Locations")
            } footer: {
                Text("The first connected location is used by default.")
            }

            Section {
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
            } header: {
                Text("Conversion")
            } footer: {
                Text("Compatible video stays unchanged; other formats convert to H.264 and AAC. Files are grouped by year, month and day.")
            }
        }
        .formStyle(.grouped)

    }

    private func locationRow(_ location: PreferredLocation, index: Int) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            Circle()
                .fill(location.resolvedURL() == nil ? Color.secondary : Color.green)
                .frame(width: Theme.Spacing.md, height: Theme.Spacing.md)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
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

            SettingsRemoveButton(label: "Remove \(location.name)") {
                settings.removeLocations(at: IndexSet(integer: index))
                onLocationsChanged()
            }
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
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.addPreferredLocation(url)
            onLocationsChanged()
        } catch {
            onError(error.localizedDescription)
        }
    }
}
