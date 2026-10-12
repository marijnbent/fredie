import AppKit
import SwiftUI

struct PermissionsSettingsView: View {
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @Environment(DictationCoordinator.self) private var dictation
    @State private var inputMonitoring = CGPreflightListenEventAccess()
    @State private var screenRecording = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: accessibilityStatus.symbol)
                                .accessibilityHidden(true)
                            Text(accessibilityStatus.title)
                        }
                        .foregroundStyle(accessibilityStatus.tint)
                        Button(accessibilityTrusted ? "Open…" : "Grant Access…") {
                            Permissions.openAccessibilitySettings()
                        }
                        .help("Opens Privacy & Security › Accessibility.")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        PermissionSettingsIcon(
                            path:
                                "/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex"
                        )
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsAccessibility, "Accessibility")
                            Text("Window switching, snippet expansion, Hyper Key, and pasting.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.permissionsAccessibility)
            }

            Section("Microphone") {
                LabeledContent("Dictation", value: dictation.permissions.microphonePermission.rawValue)
                Button("Grant Access…") { dictation.permissions.requestMicrophonePermission() }
            }
            Section("Input Monitoring") {
                LabeledContent("Typing sounds and window switching", value: inputMonitoring ? "Granted" : "Not granted")
                Button("Open Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
                }
            }
            Section("Screen Recording") {
                LabeledContent("Window previews", value: screenRecording ? "Granted" : "Not granted")
                Button("Open Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.permissions)
        .task {
            while !Task.isCancelled {
                refresh()
                dictation.permissions.refreshPermissions()
                inputMonitoring = CGPreflightListenEventAccess()
                screenRecording = CGPreflightScreenCaptureAccess()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    private var accessibilityStatus: (title: String, symbol: String, tint: Color) {
        accessibilityTrusted
            ? ("Granted", "checkmark.circle.fill", .green)
            : ("Not granted", "exclamationmark.triangle.fill", .orange)
    }

    private func refresh() {
        let trusted = Permissions.isAccessibilityTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
    }
}

private struct PermissionSettingsIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: IconCache.icon(forFile: path))
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .id(IconCache.style.generation)
            .frame(
                width: SettingsListMetrics.iconSize,
                height: SettingsListMetrics.iconSize
            )
            .accessibilityHidden(true)
    }
}
