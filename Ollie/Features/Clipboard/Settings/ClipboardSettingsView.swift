import SwiftUI

struct ClipboardSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ClipboardCoordinator.self) private var clipboard

    var body: some View {
        @Bindable var settings = settings
        Form {
            if clipboard.watcher.captureError != nil || clipboard.store.error != nil {
                Section {
                    if let error = clipboard.watcher.captureError { SettingsNotice(error) }
                    if let error = clipboard.store.error { SettingsNotice(error) }
                }
            }
            Section("Capture") {
                SettingsRow(title: "Shortcut") { ShortcutRecorder(action: .command(.clipboardHistory)) }
                SettingsRow(title: "Capture", subtitle: clipboard.watcher.isPaused ? "Paused" : "Active") {
                    Button(clipboard.watcher.isPaused ? "Resume" : "Pause") {
                        if clipboard.watcher.isPaused { clipboard.watcher.resume() } else { clipboard.watcher.pause() }
                    }
                }
            }
            Section("History") {
                Picker("Keep history", selection: $settings.clipboardHistoryDays) {
                    ForEach(ClipboardHistoryLimit.allCases, id: \.rawValue) { limit in
                        Text(limit.label).tag(limit.rawValue)
                    }
                }
                SettingsRow(title: "Saved items", subtitle: "\(clipboard.store.items.count)") {
                    Button("Open History") { clipboard.show() }
                }
                SettingsRow(title: "Export history") {
                    Button("Export JSON…") { Task { await clipboard.exportHistory() } }
                }
            }
            Section("Storage") {
                SettingsRow(title: "Images and large text") {
                    Button("Delete…", role: .destructive) {
                        Task { await clipboard.clearHistory(largeFilesOnly: true) }
                    }.disabled(!clipboard.store.hasImagesOrLargeText)
                }
                SettingsRow(title: "All history") {
                    Button("Clear…", role: .destructive) { Task { await clipboard.clearHistory() } }
                        .disabled(clipboard.store.items.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.clipboard)
    }
}

struct SnippetsSettingsView: View {
    @Environment(ClipboardCoordinator.self) private var clipboard

    private var needsAccess: Bool {
        !clipboard.snippetsRunning && !clipboard.isRecording && !clipboard.isCapturingShortcut
    }

    var body: some View {
        @Bindable var clipboard = clipboard
        return Form {
            if needsAccess || clipboard.snippets.persistenceError != nil {
                Section {
                    if needsAccess {
                        SettingsPermissionRow(title: "Accessibility") { Permissions.openAccessibilitySettings() }
                    }
                    if let error = clipboard.snippets.persistenceError { SettingsNotice(error) }
                }
            }
            Section {
                if clipboard.snippets.snippets.isEmpty {
                    Text("No snippets yet").foregroundStyle(.secondary)
                }
                ForEach(clipboard.snippets.snippets) { snippet in
                    SettingsRow(title: snippet.displayTitle, subtitle: snippet.content) {
                        Text(">\(snippet.trigger)").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                        Button("Edit…") { clipboard.snippetEditor = SnippetEditorTarget(snippet: snippet) }
                        SettingsRemoveButton(label: "Delete \(snippet.displayTitle)", deletesContent: true) {
                            Task { await clipboard.deleteSnippet(snippet) }
                        }
                    }
                }
                Button("New Snippet…") { clipboard.snippetEditor = SnippetEditorTarget(snippet: nil) }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.snippets)
        .settingsEditorPanel(item: $clipboard.snippetEditor) { target in
            SnippetEditorPanel(target: target, onDone: { clipboard.snippetEditor = nil })
        }
    }
}

struct SnippetEditorTarget: Identifiable {
    let id = UUID()
    let snippet: Snippet?
    var content: String = ""
}

private struct SnippetEditorPanel: View {
    @Environment(ClipboardCoordinator.self) private var clipboard
    let target: SnippetEditorTarget
    let onDone: () -> Void
    @State private var title: String
    @State private var trigger: String
    @State private var content: String
    @State private var error: String?

    init(target: SnippetEditorTarget, onDone: @escaping () -> Void) {
        self.target = target
        self.onDone = onDone
        _title = State(initialValue: target.snippet?.title ?? "")
        _trigger = State(initialValue: target.snippet?.trigger ?? "")
        _content = State(initialValue: target.snippet?.content ?? target.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(title: target.snippet == nil ? "New Snippet" : "Edit Snippet")
            TextField("Title", text: $title, prompt: Text("Title"))
                .settingsEditorTextField()
            TextField("Trigger", text: $trigger, prompt: Text(">trigger"))
                .settingsEditorTextField()
            TextEditor(text: $content)
                .settingsEditorTextArea(height: Theme.Size.editorTextHeight)
                .accessibilityLabel("Snippet text")
            if let error { SettingsNotice(error) }
            HStack(spacing: Theme.Spacing.md) {
                Button("Cancel", action: onDone).buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save).buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(trigger.isEmpty || content.isEmpty)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface()
    }

    private func save() {
        do {
            try clipboard.snippets.saveSnippet(id: target.snippet?.id, title: title, trigger: trigger, content: content)
            onDone()
        } catch { self.error = error.localizedDescription }
    }
}
