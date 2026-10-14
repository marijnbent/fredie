import SwiftUI

struct TypingSoundsSettingsView: View {
    @Environment(TypingSoundsCoordinator.self) private var sounds
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            if (!sounds.isRunning && !sounds.isQuiet) || sounds.isRecording {
                Section {
                    if !sounds.isRunning, !sounds.isQuiet {
                        SettingsPermissionRow(title: "Input Monitoring") { sounds.requestAccess() }
                    }
                    if sounds.isRecording {
                        LabeledContent("Playback", value: "Quiet while recording")
                    }
                }
            }
            Section("Keyboard") {
                Picker("Sound", selection: $settings.typingSoundProfile) {
                    ForEach(SoundProfile.allCases, id: \.rawValue) { profile in
                        Text(profile.menuTitle).tag(profile.rawValue)
                    }
                }
                volume("Volume", value: $settings.typingSoundVolume)
                volume("Key down", value: $settings.typingSoundDownVolume)
                volume("Key up", value: $settings.typingSoundUpVolume)
                Button("Preview") { sounds.preview() }
                    .disabled(sounds.isRecording)
            }
            Section("Mouse") {
                Toggle("Mouse clicks", isOn: $settings.typingMouseEnabled)
                volume("Click volume", value: $settings.typingMouseVolume)
                    .settingsEnabled(settings.typingMouseEnabled)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.typingSounds)
    }

    private func volume(_ title: String, value: Binding<Int>) -> some View {
        SettingsRow(title: title) {
            HStack {
                Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }), in: 0...100)
                    .accessibilityLabel(title)
                Text("\(value.wrappedValue)%").monospacedDigit().frame(width: Theme.Size.volumeReadout, alignment: .trailing)
            }
            .frame(maxWidth: Theme.Size.settingsSliderWidth)
        }
    }
}
