import SwiftUI

struct DictationGeneralSettingsView: View {
    @Bindable var viewModel: DictationSettingsController
    @State private var languageSearchText = ""
    @State private var pickerModel = DictationAppPickerState()
    @State private var isPresentingAppLanguageOverridePicker = false
    @State private var isPresentingAutomaticLanguagePicker = false

    var body: some View {
        Group {
            Section("Permissions") {
                SettingsPermissionRow(title: "Microphone", status: viewModel.microphonePermission.rawValue,
                    isGranted: viewModel.microphonePermission.isGranted,
                    actionTitle: viewModel.microphonePermission.isGranted ? "Open Settings…" : "Grant Access…") {
                        viewModel.requestMicrophonePermission()
                    }
                SettingsPermissionRow(title: "Accessibility", subtitle: "Paste transcriptions",
                    status: viewModel.accessibilityPermission.rawValue,
                    isGranted: viewModel.accessibilityPermission.isGranted, actionTitle: "Open Settings…") {
                        if viewModel.accessibilityPermission.isGranted {
                            Permissions.openAccessibilitySettings()
                        } else {
                            viewModel.requestAccessibilityPermission()
                        }
                    }
            }

            Section {
                Picker("Microphone", selection: viewModel.binding(for: \.audioInputSelection)) {
                    Text(viewModel.resolvedAudioInputSelection.systemDefaultDevice.map {
                        "System Default (\($0.name))"
                    } ?? "System Default")
                        .tag(AudioInputSelection.systemDefault)

                    ForEach(viewModel.availableAudioInputs) { input in
                        Text(input.name).tag(AudioInputSelection.device(input.id))
                    }
                }
            } header: {
                Text("Recording")
            } footer: {
                Text(viewModel.audioInputHelpText)
            }

            Section {
                Picker("Provider", selection: viewModel.binding(for: \.transcriptionProvider)) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                switch viewModel.transcriptionProvider {
                case .deepgram:
                    secret("Deepgram API key", text: viewModel.binding(for: \.apiKey))
                case .elevenLabs:
                    secret("ElevenLabs API key", text: viewModel.binding(for: \.elevenLabsApiKey))
                case .assemblyAI:
                    secret("AssemblyAI API key", text: viewModel.binding(for: \.assemblyAIApiKey))
                    if let error = viewModel.assemblyAIKeyError {
                        SettingsNotice(error)
                    }
                case .muse:
                    secret("Muse API key", text: viewModel.binding(for: \.museApiKey))
                }

                Picker("Current language", selection: viewModel.languageBinding()) {
                    ForEach(viewModel.availableLanguages) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                if viewModel.supportsAutomaticLanguageCandidates {
                    LabeledContent("Automatic languages") {
                        HStack(spacing: Theme.Spacing.lg) {
                            Text(viewModel.automaticLanguageCandidatesSummary)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Button("Edit…") {
                                isPresentingAutomaticLanguagePicker = true
                            }
                            .settingsEditorPanel(isPresented: $isPresentingAutomaticLanguagePicker) {
                                AutomaticLanguagePickerPanel(viewModel: viewModel)
                            }
                        }
                    }
                }
            } header: {
                Text("Speech to Text")
            } footer: {
                Text(viewModel.transcriptionLanguageHelpText)
            }

            Section {
                Toggle(isOn: viewModel.binding(for: \.showSelectedLanguageInMenuBar)) {
                    Text("Show selected language in menu bar")
                    Text("Hidden when Automatic is selected.")
                }
                Toggle("Show language button in recorder widget", isOn: viewModel.binding(for: \.showLanguageInRecorderWidget))

                SettingsFilterField(prompt: "Search languages", query: $languageSearchText)

                if viewModel.menuBarLanguages(matching: languageSearchText).isEmpty {
                    Text("No languages found")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            ForEach(viewModel.menuBarLanguages(matching: languageSearchText)) { language in
                                MenuBarLanguageSettingsRow(
                                    language: language,
                                    isCurrent: viewModel.selectedLanguage == language,
                                    isStarred: viewModel.isLanguageStarred(language),
                                    canToggleStarRemoval: viewModel.canToggleStarRemoval(for: language),
                                    onToggleStar: { viewModel.toggleStar(for: language) }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 12)
                    }
                    .frame(minHeight: 160, maxHeight: 220)
                }
            } header: {
                Text("Menu Bar Languages")
            } footer: {
                Text("Only starred languages appear in the menu bar language submenu.")
            }

            appLanguageOverridesSection

            Section("Behavior") {
                Toggle("Cancel recording with Escape", isOn: viewModel.binding(for: \.escToCancelRecording))
                Toggle("Play sound effects", isOn: viewModel.binding(for: \.playSoundEffects))
                Toggle("Mute during recording", isOn: viewModel.binding(for: \.muteMediaDuringRecording))
                Toggle("Restore clipboard after confirmed auto-paste", isOn: viewModel.binding(for: \.restoreClipboardAfterPaste))
                Toggle("Show live transcript in recorder widget", isOn: viewModel.binding(for: \.showLiveTranscriptInRecorderWidget))
                Picker("Widget position", selection: viewModel.binding(for: \.overlayPosition)) {
                    ForEach(OverlayPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
            }

            Section("History") {
                Picker("Keep history", selection: viewModel.binding(for: \.historyLimit)) {
                    ForEach(DictationHistoryLimit.allCases) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
            }
        }

    }

    private func secret(_ title: String, text: Binding<String>) -> some View {
        SettingsRow(title: "API key") {
            RevealableSecureField(title: title, text: text, prompt: Text("API key"))
                .labelsHidden()
                .frame(width: Theme.Size.settingsSecretWidth)
        }
    }

    @ViewBuilder
    private var appLanguageOverridesSection: some View {
        Section {
            if viewModel.appTranscriptionLanguageOverrides.isEmpty {
                Text("No app languages")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.appTranscriptionLanguageOverrides) { override in
                    if let overrideBinding = viewModel.bindingForAppTranscriptionLanguageOverrideID(override.id) {
                        AppLanguageOverrideRow(
                            overrideBinding: overrideBinding,
                            availableLanguages: viewModel.appOverrideLanguages(for: override.language),
                            onRemove: {
                                viewModel.removeAppTranscriptionLanguageOverride(id: override.id)
                            }
                        )
                    }
                }
            }

            Button("Add App…") {
                isPresentingAppLanguageOverridePicker = true
            }
            .settingsEditorPanel(isPresented: $isPresentingAppLanguageOverridePicker) {
                RunningAppPickerPanel(model: pickerModel) { app in
                    viewModel.upsertAppTranscriptionLanguageOverride(
                        appBundleIdentifier: app.bundleIdentifier,
                        appDisplayName: app.displayName
                    )
                }
            }
        } header: {
            Text("App Languages")
        } footer: {
            Text("Apps without an override use the default language: \(viewModel.selectedLanguage.displayName).")
        }
    }
}

private struct AutomaticLanguagePickerPanel: View {
    @Bindable var viewModel: DictationSettingsController
    @Environment(\.settingsEditorDismiss) private var dismiss
    @State private var searchText = ""

    private var filteredLanguages: [DeepgramLanguage] {
        viewModel.automaticLanguageCandidateOptions.filter { $0.matchesSearch(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SettingsEditorHeader(title: "Automatic Languages")
                Text("Select at least two languages. Automatic detection will ignore other languages.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            SettingsFilterField(prompt: "Search languages", query: $searchText)

            if filteredLanguages.isEmpty {
                Text("No languages found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredLanguages) { language in
                    let isSelected = viewModel.isAutomaticLanguageCandidate(language)
                    Button {
                        viewModel.toggleAutomaticLanguageCandidate(language)
                    } label: {
                        HStack(spacing: Theme.Spacing.lg) {
                            Text(language.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSelected && !viewModel.canRemoveAutomaticLanguageCandidate(language))
                }
                .listStyle(.inset)
            }

            HStack {
                Text("\(viewModel.automaticLanguageCandidates.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth, height: Theme.Size.settingsPickerHeight)
        .settingsEditorPanelSurface(controlsOnGlass: false)
    }
}

private struct MenuBarLanguageSettingsRow: View {
    let language: DeepgramLanguage
    let isCurrent: Bool
    let isStarred: Bool
    let canToggleStarRemoval: Bool
    let onToggleStar: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(language.displayName)

                if isCurrent {
                    Text("Current selection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onToggleStar) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundStyle(isStarred ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isStarred && !canToggleStarRemoval)
            .accessibilityLabel(isStarred ? "Remove star" : "Add star")
            .help(isStarred ? "Remove from menu bar languages" : "Add to menu bar languages")
        }
    }
}

private struct AppLanguageOverrideRow: View {
    @Binding var overrideBinding: AppTranscriptionLanguageOverride
    let availableLanguages: [DeepgramLanguage]
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            BundleIconView(
                bundleIdentifier: overrideBinding.appBundleIdentifier,
                bundleURL: nil,
                size: SettingsListMetrics.iconSize
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(overrideBinding.appDisplayName)
                    .font(.body)
                Text(overrideBinding.appBundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Picker("Language", selection: $overrideBinding.language) {
                ForEach(availableLanguages) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 220)
            .labelsHidden()

            SettingsRemoveButton(label: "Remove app language", action: onRemove)
        }
        .padding(.vertical, 2)
    }
}
