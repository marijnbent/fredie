import SwiftUI

struct CompactMenuView: View {
    let core: AppCore
    let close: () -> Void
    @State private var optionsHovered = false
    @State private var notificationsHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Bundle.main.appDisplayName).font(.system(size: 13, weight: .medium))
                Spacer()
                Menu {
                    Button("Check for Updates…") { perform { core.updateCoordinator.checkForUpdates() } }
                    Button("About \(Bundle.main.appDisplayName)") { perform { core.settingsCoordinator.showAbout() } }
                    Divider()
                    Button("Quit \(Bundle.main.appDisplayName)") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(optionsHovered ? Theme.Colors.rowHover : .clear,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.barControl))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("App options")
                .onHover { optionsHovered = $0 }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(height: 42)
            if core.dictation.isBusy {
                HStack(spacing: 10) {
                    Image(systemName: core.dictation.session.isRecording ? "waveform" : "ellipsis").foregroundStyle(.red)
                    Text(core.dictation.session.statusMessage).font(.system(size: 11)).lineLimit(1)
                    Spacer()
                    if core.dictation.session.isRecording {
                        Button("Stop") { core.dictation.toggleRecording() }.controlSize(.small)
                    }
                    Button("Cancel") { core.dictation.cancelRecording() }.controlSize(.small)
                }.padding(.horizontal, 16).padding(.vertical, 10)
            }
            if core.mediaImport.state.isImporting {
                HStack(spacing: 10) {
                    ProgressView(value: core.mediaImport.state.overallImportProgress).frame(width: 38)
                    Text("Importing \(core.mediaImport.state.completedCount)/\(core.mediaImport.state.totalImportCount)")
                        .font(.system(size: 11)).monospacedDigit()
                    Spacer()
                    Button("Cancel") { core.mediaImport.state.cancelImport() }.controlSize(.small)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            if core.settings.notificationsEnabled {
                Button {
                    perform { core.settingsCoordinator.showSettings(tab: .notifications) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bell").frame(width: 22)
                        Text("Notifications").font(.system(size: 12, weight: .medium))
                        Spacer()
                        if core.notifications.unread > 0 {
                            Text("\(core.notifications.unread)")
                                .font(.system(size: 11)).monospacedDigit()
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 40)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.barControl))
                    .background(notificationsHovered ? Theme.Colors.rowHover : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.barControl))
                }
                .buttonStyle(.plain)
                .onHover { notificationsHovered = $0 }
                .padding(.horizontal, 8)
            }
            if core.settings.networkEnabled {
                NetworkMenuSection(network: core.network) {
                    perform { core.settingsCoordinator.showSettings(tab: .network) }
                }
            }
            if core.dictation.isBusy || core.mediaImport.state.isImporting
                || core.settings.notificationsEnabled || core.settings.networkEnabled {
                Rectangle().fill(Theme.Colors.separator).frame(height: 0.5)
                    .padding(.horizontal, 16).padding(.top, 6)
            }
            HStack(spacing: 4) {
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
                ActionButton(
                    title: "Typing Sounds",
                    symbol: core.settings.typingSoundsEnabled ? "speaker.wave.2" : "speaker.slash",
                    selected: core.settings.typingSoundsEnabled
                ) { core.settings.typingSoundsEnabled.toggle() }
                .accessibilityValue(core.settings.typingSoundsEnabled ? "On" : "Off")
                action("Settings", symbol: "gearshape") { core.settingsCoordinator.showSettings() }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(width: 320)
        .fixedSize(horizontal: true, vertical: true)
        .background(HUDGlassBackground().allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Size.floatingRadius, style: .continuous))
    }

    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        ActionButton(title: title, symbol: symbol) { perform(run) }
    }

    private struct ActionButton: View {
        let title: String
        let symbol: String
        var selected = false
        let run: () -> Void
        @State private var hovered = false

        var body: some View {
            Button(action: run) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : Theme.Colors.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.barControl))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.barControl))
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .help(title)
            .accessibilityLabel(title)
        }
    }

    private func perform(_ action: () -> Void) {
        close()
        action()
    }
}
