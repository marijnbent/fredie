#if DEBUG
import AppKit
import Carbon.HIToolbox

@MainActor
enum LauncherInputVerification {
    static func run() async throws {
        let core = AppCore.shared
        core.settings.launcherEnabled = true
        core.settings.compactMode = false
        core.appIndex.start(settings: core.settings)
        await core.appIndex.refresh()
        NSApp.setActivationPolicy(.accessory)
        var failures: [String] = []
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL"): \(label)")
            if !condition { failures.append(label) }
        }
        defer { core.paletteCoordinator.hidePalette(restoreFocus: false) }
        core.paletteCoordinator.showPalette(mode: .launcher, seeding: "")
        try await Task.sleep(for: .milliseconds(400))
        guard let panel = NSApp.windows.compactMap({ $0 as? PalettePanel }).first(where: \.isVisible) else {
            throw CocoaError(.coderValueNotFound)
        }
        check(panel.isKeyWindow, "summoning gives the launcher keyboard focus")
        key(kVK_Escape, characters: "\u{1b}", in: panel)
        try await Task.sleep(for: .milliseconds(200))
        check(!core.paletteCoordinator.isVisible, "Escape closes an empty launcher")
        core.paletteCoordinator.showPalette(mode: .launcher, seeding: "")
        try await Task.sleep(for: .milliseconds(250))
        check(panel.isKeyWindow, "reopening restores keyboard focus")
        typeQuery(in: panel)
        try await Task.sleep(for: .milliseconds(150))
        check(core.palette.query == "emoji", "typing reaches the search model")
        key(kVK_Escape, characters: "\u{1b}", in: panel)
        try await Task.sleep(for: .milliseconds(150))
        check(core.palette.query.isEmpty && core.paletteCoordinator.isVisible, "Escape first clears a nonempty query")
        key(kVK_Escape, characters: "\u{1b}", in: panel)
        try await Task.sleep(for: .milliseconds(150))
        check(!core.paletteCoordinator.isVisible, "second Escape closes the launcher")
        for keyCode in [kVK_Return, kVK_ANSI_KeypadEnter] {
            core.paletteCoordinator.showPalette(mode: .launcher, seeding: "")
            try await Task.sleep(for: .milliseconds(250))
            check(panel.isKeyWindow, "keyboard focus before key \(keyCode)")
            typeQuery(in: panel)
            try await Task.sleep(for: .milliseconds(200))
            let results = core.appIndex.appResults(
                query: core.palette.query, visibility: core.visibility, favorites: core.favorites, fallbackLimit: 12)
            guard let index = results.entries.firstIndex(where: { $0.id == CommandID.searchEmoji.rawValue }) else {
                throw CocoaError(.coderValueNotFound)
            }
            core.palette.selection = index
            try await Task.sleep(for: .milliseconds(100))
            key(keyCode, characters: keyCode == kVK_Return ? "\r" : "\u{3}", in: panel)
            try await Task.sleep(for: .milliseconds(250))
            check(core.palette.mode == .emoji, "key \(keyCode) activates the selected launcher result")
        }
        if !failures.isEmpty { throw NSError(domain: "LauncherInputVerification", code: failures.count) }
    }

    private static func typeQuery(in window: NSWindow) {
        let keys = [(kVK_ANSI_E, "e"), (kVK_ANSI_M, "m"), (kVK_ANSI_O, "o"), (kVK_ANSI_J, "j"), (kVK_ANSI_I, "i")]
        for (code, character) in keys { key(code, characters: character, in: window) }
    }

    private static func key(_ code: Int, characters: String, in window: NSWindow) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code)
        ) else { return }
        NSApp.sendEvent(event)
    }
}
#endif
