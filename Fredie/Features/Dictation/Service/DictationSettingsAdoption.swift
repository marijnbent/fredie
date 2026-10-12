import Foundation
import Security
import LocalAuthentication

extension DictationSettingsStore {
    func adopt(_ values: [String: Any]) throws {
        loadCredentials()
        guard credentialError == nil else { throw LegacyDataCopy.Failure.invalid }
        let importedShortcuts = try (values[Self.shortcutsKey] as? Data).map { try JSONDecoder().decode([ShortcutConfig].self, from: $0) }
        let importedPrompts = try (values[Self.promptsKey] as? Data).map { try JSONDecoder().decode([PromptConfig].self, from: $0) }
        let importedApptranscriptionlanguageoverrides = try (values[Self.appTranscriptionLanguageOverridesKey] as? Data).map { try JSONDecoder().decode([AppTranscriptionLanguageOverride].self, from: $0) }
        if let shortcuts = importedShortcuts {
            guard Set(shortcuts.map(\.id)).count == shortcuts.count, Set(shortcuts.map(\.key)).count == shortcuts.count else { throw LegacyDataCopy.Failure.invalid }
        }
        if let raw = values[Self.transcriptionProviderKey] as? String, let value = TranscriptionProvider(rawValue: raw) { transcriptionProvider = value }
        if let raw = values[Self.deepgramLanguageKey] as? String, let value = DeepgramLanguage(rawValue: raw) { deepgramLanguage = value }
        if let raw = values[Self.overlayPositionKey] as? String, let value = OverlayPosition(rawValue: raw) { overlayPosition = value }
        if let raw = values["Talkie.HistoryLimit"] as? Int, let value = DictationHistoryLimit(rawValue: raw) { historyLimit = value }
        if let value = values[Self.escToCancelRecordingKey] as? Bool { escToCancelRecording = value }
        if let value = values[Self.playSoundEffectsKey] as? Bool { playSoundEffects = value }
        if let value = values[Self.muteMediaDuringRecordingKey] as? Bool { muteMediaDuringRecording = value }
        if let value = values[Self.restoreClipboardAfterPasteKey] as? Bool { restoreClipboardAfterPaste = value }
        if let value = values[Self.showLanguageInRecorderWidgetKey] as? Bool { showLanguageInRecorderWidget = value }
        if let value = values[Self.showLiveTranscriptInRecorderWidgetKey] as? Bool { showLiveTranscriptInRecorderWidget = value }
        if let value = importedShortcuts { shortcuts = value }
        if let value = importedPrompts { prompts = value }
        if let value = importedApptranscriptionlanguageoverrides { appTranscriptionLanguageOverrides = value }
        if let value = values[Self.audioInputSelectionKey] as? String { audioInputSelection = AudioInputSelection(storedValue: value) }
        if let values = values[Self.automaticLanguageCandidatesKey] as? [String] { automaticLanguageCandidates = values.compactMap(DeepgramLanguage.init(rawValue:)) }
        if let values = values[Self.starredDeepgramLanguagesKey] as? [String] { starredDeepgramLanguages = values.compactMap(DeepgramLanguage.init(rawValue:)) }
        let keys: [(String, DictationCredential, ReferenceWritableKeyPath<DictationSettingsStore, String>)] = [
            (Self.apiKeyKey, .deepgram, \.apiKey), (Self.elevenLabsApiKeyKey, .elevenLabs, \.elevenLabsApiKey),
            (Self.museApiKeyKey, .muse, \.museApiKey), (Self.openRouterApiKeyKey, .openRouter, \.openRouterApiKey),
            (Self.celerisApiKeyKey, .celeris, \.celerisApiKey)
        ]
        for (key, kind, path) in keys {
            guard self[keyPath: path].isEmpty, let value = values[key] as? String, !value.trimmed.isEmpty else { continue }
            try DictationCredential.store.setSecret(value.trimmed, for: kind.account)
            self[keyPath: path] = value.trimmed
        }
        if assemblyAIApiKey.isEmpty {
            let context = LAContext()
            context.interactionNotAllowed = true
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "nl.bentjes.talkie.assemblyai", kSecAttrAccount as String: "api-key",
                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: context]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty {
                try DictationCredential.store.setSecret(value, for: DictationCredential.assemblyAI.account)
                assemblyAIApiKey = value
            } else if status != errSecItemNotFound && status != errSecSuccess {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Talkie’s AssemblyAI key could not be read. Other data was imported; enter this key in Dictation settings."])
            }
        }
    }
}
