import SwiftUI

struct TypingSoundsSettingsView: View {
    @Environment(TypingSoundsCoordinator.self) private var sounds
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                if settings.typingSoundsEnabled, !sounds.isRunning, !sounds.isQuiet {
                    LabeledContent("Input Monitoring", value: "Not granted")
                    Button("Grant Access…") { sounds.requestAccess() }
                }
                if sounds.isRecording {
                    Text("Quiet while recording").foregroundStyle(.secondary)
                }
            }
            Section {
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
            Section {
                Toggle("Mouse clicks", isOn: $settings.typingMouseEnabled)
                volume("Click volume", value: $settings.typingMouseVolume)
                    .disabled(!settings.typingMouseEnabled)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.typingSounds)
    }

    private func volume(_ title: String, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }), in: 0...100)
                    .accessibilityLabel(title)
                Text("\(value.wrappedValue)%").monospacedDigit().frame(width: 38, alignment: .trailing)
            }
            .frame(maxWidth: 220)
        }
    }
}
