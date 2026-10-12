import AppKit
import Observation
import Security

@MainActor @Observable
final class LegacyDataCoordinator {
    private unowned let core: AppCore
    private(set) var active: LegacyApp?
    private(set) var status: [LegacyApp: String] = [:]
    @ObservationIgnored private var operation: Task<Void, Never>?

    init(core: AppCore) { self.core = core }

    func isEnabled(_ app: LegacyApp) -> Bool {
        switch app {
        case .clipboard: core.settings.clipboardEnabled || core.settings.snippetsEnabled
        case .dictation: core.settings.dictationEnabled
        case .windowSwitcher: core.settings.windowSwitcherEnabled
        case .typingSounds: core.settings.typingSoundsEnabled
        case .mediaImport: core.settings.mediaImportEnabled
        case .notifications: core.settings.notificationsEnabled
        case .network: core.settings.networkEnabled
        }
    }

    func unavailable(_ app: LegacyApp) -> String? {
        if core.legacyApps.isRunning(app) { return "Quit \(app.name) first" }
        if isEnabled(app) { return "Turn off this feature first" }
        return nil
    }

    func importData(_ app: LegacyApp) {
        guard active == nil, unavailable(app) == nil else { return }
        operation = Task { [weak self] in
            guard let self else { return }
            guard await core.confirm(title: "Import from \(app.name)?", message: "Copy saved data and settings into Ollie. Existing Ollie history and the original app data are kept. Dictation API keys are copied into Ollie’s Keychain.", symbol: "square.and.arrow.down", confirmTitle: "Import"),
                  unavailable(app) == nil, active == nil else { return }
            active = app
            defer { active = nil; operation = nil }
            do {
                var shortcutNotice: String?
                let values = UserDefaults.standard.persistentDomain(forName: app.rawValue) ?? [:]
                switch app {
                case .clipboard:
                    guard await core.clipboard.prepareForTermination() else { throw LegacyDataCopy.Failure.existing }
                    if let data = values["savedSnippets"] as? Data {
                        _ = try JSONDecoder().decode([Snippet].self, from: data)
                        guard core.clipboard.snippets.snippets.isEmpty else { throw LegacyDataCopy.Failure.existing }
                    }
                    try await copy(app, source: "clippie", destination: "Clipboard", kind: "clipboard", allowMissing: !values.isEmpty)
                    if let data = values["savedSnippets"] as? Data { UserDefaults.standard.set(data, forKey: "savedSnippets") }
                    if let days = values["historyLimit"] as? Int, ClipboardHistoryLimit(rawValue: days) != nil { core.settings.clipboardHistoryDays = days }
                    shortcutNotice = adoptClipboardShortcut(values)
                    await core.clipboard.reloadAdoptedData()
                case .dictation:
                    guard await core.dictation.prepareForTermination() else { throw LegacyDataCopy.Failure.existing }
                    try await copy(app, source: "Talkie", destination: "Dictation", kind: "dictation", allowMissing: !values.isEmpty)
                    try core.dictation.settings.adopt(values)
                    await core.dictation.reloadAdoptedData()
                case .network:
                    core.network.stop()
                    try await copy(app, source: "Nettie", destination: "Network", kind: "network")
                case .mediaImport:
                    core.mediaImport.stop()
                    let locations = try (values["Importie.PreferredLocations"] as? Data).map { try JSONDecoder().decode([PreferredLocation].self, from: $0) }
                    try await copy(app, source: "Importie", destination: "MediaImport", kind: "mediaImport", allowMissing: !values.isEmpty)
                    if let locations { core.mediaImport.state.settingsStore.adoptLocations(locations) }
                    if let open = values["Importie.OpenOnDetection"] as? Bool { core.mediaImport.state.settingsStore.openOnDetection = open }
                    try core.mediaImport.state.ledger.reload()
                    core.mediaImport.state.refreshDestinations()
                case .windowSwitcher:
                    guard let data = values["tabbie.settings"] as? Data else { throw LegacyDataCopy.Failure.missing }
                    let settings = try JSONDecoder().decode(SwitcherSettings.self, from: data)
                    core.settings.switcherCommandTab = settings.activationShortcuts.contains(.commandTab)
                    core.settings.switcherCommandBacktick = settings.activationShortcuts.contains(.commandBacktick)
                    core.settings.switcherWindowSource = settings.windowSource.rawValue
                    core.settings.switcherMinimizedMode = settings.minimizedMode.rawValue
                    core.settings.switcherHiddenMode = settings.hiddenMode.rawValue
                    core.settings.switcherAppsWithoutWindowsMode = settings.appsWithoutWindowsMode.rawValue
                    core.settings.switcherImmediatePreview = settings.switchWindowsImmediately
                    core.settings.switcherDiagnostics = settings.diagnosticsEnabled
                case .typingSounds:
                    guard !values.isEmpty else { throw LegacyDataCopy.Failure.missing }
                    if let profile = values["soundProfile"] as? String, SoundProfile(rawValue: profile) != nil { core.settings.typingSoundProfile = profile }
                    for (key, path) in [("volume", \AppSettings.typingSoundVolume), ("downVolume", \AppSettings.typingSoundDownVolume), ("upVolume", \AppSettings.typingSoundUpVolume), ("mouseVolume", \AppSettings.typingMouseVolume)] {
                        if let value = values[key] as? Double { core.settings[keyPath: path] = min(100, max(0, Int(value * 100))) }
                    }
                    if let enabled = values["mouseClicksEnabled"] as? Bool { core.settings.typingMouseEnabled = enabled }
                case .notifications:
                    return
                }
                status[app] = shortcutNotice ?? "Imported"
            } catch { status[app] = error.localizedDescription }
        }
    }

    private func adoptClipboardShortcut(_ values: [String: Any]) -> String? {
        let action = HotKeyAction.command(.clipboardHistory)
        guard core.hotKeys.binding(for: action) == nil else { return nil }
        let names = values["hotkeyModifiers"] as? [String] ?? ["option"]
        var modifiers: NSEvent.ModifierFlags = []
        for (name, flag) in [("command", NSEvent.ModifierFlags.command), ("option", .option), ("control", .control), ("shift", .shift)] where names.contains(name) {
            modifiers.insert(flag)
        }
        guard let shortcut = KeyShortcut(keyCode: values["hotkeyKeyCode"] as? Int ?? 44, modifierFlags: modifiers) else { return nil }
        let binding = HotKeyBinding.combo(shortcut)
        if let owner = core.hotKeys.conflictOwner(of: binding, excluding: action) {
            return "Imported. Clipboard shortcut is already used by \(owner)."
        }
        core.hotKeys.setBinding(binding, for: action)
        return nil
    }

    private func copy(_ app: LegacyApp, source: String, destination: String, kind: String, allowMissing: Bool = false) async throws {
        let source = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(source)
        let destination = AppPaths.applicationSupport().appendingPathComponent(destination)
        let file = kind == "clipboard" ? "history.json" : kind == "dictation" ? "transcript-history.json" : kind == "network" ? "usage.sqlite" : "ImportLedger.json"
        if allowMissing, !FileManager.default.fileExists(atPath: source.appendingPathComponent(file).path) { return }
        guard !core.legacyApps.isRunning(app) else { throw LegacyDataCopy.Failure.invalid }
        try await Task.detached(priority: .utility) { try LegacyDataCopy.copy(source: source, destination: destination, kind: kind) }.value
    }

    func finish() async { if active != nil { await operation?.value } }
}
