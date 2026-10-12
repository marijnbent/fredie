import SwiftUI

struct CompactMenuView: View {
    let core: AppCore
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Bundle.main.appDisplayName).font(.system(size: 13, weight: .semibold))
                Spacer()
                Menu {
                    Button("Check for Updates…") { perform { core.updateCoordinator.checkForUpdates() } }
                    Button("About \(Bundle.main.appDisplayName)") { perform { core.settingsCoordinator.showAbout() } }
                    Divider()
                    Button("Quit \(Bundle.main.appDisplayName)") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 26, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("App options")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)
            if core.dictation.isBusy {
                HStack(spacing: 10) {
                    Image(systemName: core.dictation.session.isRecording ? "waveform" : "ellipsis").foregroundStyle(.red)
                    Text(core.dictation.session.statusMessage).font(.system(size: 11)).lineLimit(1)
                    Spacer()
                    if core.dictation.session.isRecording {
                        Button("Stop") { core.dictation.toggleRecording() }.controlSize(.small)
                    }
                    Button("Cancel") { core.dictation.cancelRecording() }.controlSize(.small)
                }.padding(.horizontal, 14).padding(.vertical, 10)
            }
            if core.mediaImport.state.isImporting {
                HStack(spacing: 10) {
                    ProgressView(value: core.mediaImport.state.overallImportProgress).frame(width: 38)
                    Text("Importing \(core.mediaImport.state.completedCount)/\(core.mediaImport.state.totalImportCount)")
                        .font(.system(size: 11)).monospacedDigit()
                    Spacer()
                    Button("Cancel") { core.mediaImport.state.cancelImport() }.controlSize(.small)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            if core.settings.notificationsEnabled {
                Button {
                    perform { core.settingsCoordinator.showSettings(tab: .notifications) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bell").frame(width: 22)
                        Text("Notifications").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(core.notifications.unread == 0 ? "No unread" : "\(core.notifications.unread) unread")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            if core.settings.networkEnabled {
                NetworkMenuSection(network: core.network) {
                    perform { core.settingsCoordinator.showSettings(tab: .network) }
                }
                Divider().padding(.horizontal, 12).padding(.bottom, 6)
            }
            HStack(spacing: 5) {
                if core.settings.launcherEnabled {
                    action("Launcher", symbol: "square.grid.2x2") { core.paletteCoordinator.showPalette(mode: .launcher) }
                }
                if core.settings.clipboardEnabled || core.settings.snippetsEnabled {
                    action("Clipboard", symbol: "clipboard") { core.clipboard.show() }
                }
                if core.settings.dictationEnabled {
                    action("Dictate", symbol: "mic") { core.dictation.toggleRecording() }
                }
                if core.settings.aiEnabled {
                    action("AI Chat", symbol: "sparkles") { core.aiChatCoordinator.showWindow() }
                }
                if core.settings.mediaImportEnabled {
                    action("Media Import", symbol: "externaldrive.badge.plus") { core.mediaImport.show() }
                }
                Spacer(minLength: 0)
                Button {
                    core.settings.typingSoundsEnabled.toggle()
                } label: {
                    Image(systemName: core.settings.typingSoundsEnabled ? "speaker.wave.2" : "speaker.slash")
                        .frame(width: 34, height: 32)
                        .foregroundStyle(core.settings.typingSoundsEnabled ? Color.accentColor : .secondary)
                }
                .help("Typing Sounds")
                .accessibilityLabel("Typing Sounds")
                .accessibilityValue(core.settings.typingSoundsEnabled ? "On" : "Off")
                action("Settings", symbol: "gearshape") { core.settingsCoordinator.showSettings() }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 9)
            .padding(.bottom, 9)
        }
        .frame(width: 320)
        .fixedSize(horizontal: true, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.1)))
    }

    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        Button { perform(run) } label: {
            Image(systemName: symbol).frame(width: 34, height: 32)
        }
        .help(title)
        .accessibilityLabel(title)
    }

    private func perform(_ action: () -> Void) {
        close()
        action()
    }
}
