import Foundation

/// The per-channel storage roots. Keyed by bundle id so a Dev build never shares a stable's dirs.
enum AppPaths {
    static func caches(
        bundleID: String = Bundle.main.bundleIdentifier ?? "nl.bentjes.fredie"
    ) -> URL {
        root(.cachesDirectory, bundleID: bundleID)
    }

    static func applicationSupport(
        bundleID: String = Bundle.main.bundleIdentifier ?? "nl.bentjes.fredie"
    ) -> URL {
        root(.applicationSupportDirectory, bundleID: bundleID)
    }

    /// `~/.config/fredie/settings.json`; another channel suffixes the folder, as `fredie-dev`.
    static func settingsFile(
        bundleID: String = Bundle.main.bundleIdentifier ?? "nl.bentjes.fredie"
    ) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config", directoryHint: .isDirectory)
            .appending(path: configFolderName(bundleID: bundleID), directoryHint: .isDirectory)
            .appending(path: "settings.json", directoryHint: .notDirectory)
    }

    static func contentFolder(
        _ chosen: String?, named name: String,
        bundleID: String = Bundle.main.bundleIdentifier ?? "nl.bentjes.fredie"
    ) -> URL {
        guard let chosen, isFolderPath(chosen) else {
            return applicationSupport(bundleID: bundleID).appending(path: name, directoryHint: .isDirectory)
        }
        // Resolved once here, so a folder that is itself a symlink lists like any other.
        return URL(filePath: (chosen as NSString).expandingTildeInPath, directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
    }

    /// How a chosen folder is stored: nil for the default, else `~`-relative where it can be.
    static func contentFolderSetting(
        for url: URL, named name: String,
        bundleID: String = Bundle.main.bundleIdentifier ?? "nl.bentjes.fredie"
    ) -> String? {
        let chosen = url.standardizedFileURL.resolvingSymlinksInPath()
        let standard = contentFolder(nil, named: name, bundleID: bundleID).resolvingSymlinksInPath()
        guard chosen.path != standard.path else { return nil }
        return (chosen.path as NSString).abbreviatingWithTildeInPath
    }

    /// Absolute, or under `~/`, so the same path means the same folder on every Mac.
    static func isFolderPath(_ path: String) -> Bool {
        path.hasPrefix("/") || path.hasPrefix("~/")
    }

    private static func configFolderName(bundleID: String) -> String {
        let stable = "nl.bentjes.fredie"
        if bundleID == stable { return "fredie" }
        guard bundleID.hasPrefix(stable + ".") else { return bundleID }
        return "fredie-" + bundleID.dropFirst(stable.count + 1)
    }

    private static func root(
        _ directory: FileManager.SearchPathDirectory, bundleID: String
    ) -> URL {
        let url = FileManager.default
            .urls(for: directory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
