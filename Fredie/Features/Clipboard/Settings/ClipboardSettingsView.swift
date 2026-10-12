import SwiftUI

struct ClipboardSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ClipboardCoordinator.self) private var clipboard

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Clipboard history", isOn: $settings.clipboardEnabled)
                LegacyAppNotice(app: .clipboard)
                LabeledContent("Shortcut") { ShortcutRecorder(action: .command(.clipboardHistory)) }
                Picker("Keep history", selection: $settings.clipboardHistoryDays) {
                    ForEach(ClipboardHistoryLimit.allCases, id: \.rawValue) { limit in
                        Text(limit.label).tag(limit.rawValue)
                    }
                }
                HStack {
                    Button("Open History") { clipboard.show() }
                        .disabled(!settings.clipboardEnabled && !settings.snippetsEnabled)
                    if settings.clipboardEnabled {
                        Button(clipboard.watcher.isPaused ? "Resume" : "Pause") {
                            if clipboard.watcher.isPaused { clipboard.watcher.resume() } else { clipboard.watcher.pause() }
                        }
                    }
                }
                if let error = clipboard.watcher.captureError { Text(error).foregroundStyle(.red) }
                if let error = clipboard.store.error { Text(error).foregroundStyle(.red) }
            }
            Section {
                LabeledContent("Saved items", value: "\(clipboard.store.items.count)")
                Button("Export as JSON…") { Task { await clipboard.exportHistory() } }
                Button("Delete Images and Large Text…", role: .destructive) {
                    Task { await clipboard.clearHistory(largeFilesOnly: true) }
                }.disabled(!clipboard.store.hasImagesOrLargeText)
                Button("Clear History…", role: .destructive) { Task { await clipboard.clearHistory() } }
                    .disabled(clipboard.store.items.isEmpty)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.clipboard)
    }
}

struct SnippetsSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ClipboardCoordinator.self) private var clipboard
    @State private var selected: UUID?
    @State private var title = ""
    @State private var trigger = ""
    @State private var content = ""
    @State private var error: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Expand snippets", isOn: $settings.snippetsEnabled)
                LegacyAppNotice(app: .clipboard)
                if settings.snippetsEnabled, !clipboard.snippetsRunning, !clipboard.isRecording, !clipboard.isCapturingShortcut {
                    Button("Grant Accessibility Access…") { Permissions.openAccessibilitySettings() }
                }
                if let error = clipboard.snippets.persistenceError { Text(error).foregroundStyle(.red) }
            }
            Section {
                ForEach(clipboard.snippets.snippets) { snippet in
                    HStack {
                        Button {
                            selected = snippet.id
                            title = snippet.title
                            trigger = snippet.trigger
                            content = snippet.content
                            error = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(":\(snippet.trigger)").fontWeight(.medium)
                                Text(snippet.content).lineLimit(1).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                        Spacer()
                        Button(role: .destructive) { Task { await clipboard.deleteSnippet(snippet) } } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless).accessibilityLabel("Delete :\(snippet.trigger)")
                    }
                }
                Button("New Snippet") { reset() }
            }
            Section(selected == nil ? "New Snippet" : "Edit Snippet") {
                TextField("Title", text: $title)
                TextField("Trigger", text: $trigger, prompt: Text(":trigger"))
                TextEditor(text: $content).frame(minHeight: 120).accessibilityLabel("Snippet text")
                if let error { Text(error).foregroundStyle(.red) }
                Button("Save") {
                    do {
                        try clipboard.snippets.saveSnippet(id: selected, title: title, trigger: trigger, content: content)
                        reset()
                    } catch { self.error = error.localizedDescription }
                }.disabled(trigger.isEmpty || content.isEmpty)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.snippets)
    }

    private func reset() {
        selected = nil
        title = ""
        trigger = ""
        content = ""
        error = nil
    }
}
