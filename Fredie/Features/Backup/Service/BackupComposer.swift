import Foundation

/// Stores → staged bundle: `plan` reads on the main actor, `write` does every byte of IO off it.
@MainActor
enum BackupComposer {
    /// Everything the writer needs, in `Sendable` form, so the heavy half can leave the actor.
    struct Plan: Sendable {
        var categories: Set<BackupCategory>
        var appVersion: String
        var settings: Data?
        var notesDirectory: URL?
        var learning: [BackupBundle.LearningPart: Data] = [:]
        var learningRecords = 0
    }

    struct Result: Sendable {
        var manifest: BackupManifest
    }

    static func plan(_ categories: Set<BackupCategory>, from core: AppCore) -> Plan {
        var plan = Plan(
            categories: categories,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "unknown")
        if categories.contains(.configuration) {
            plan.settings = try? SettingsBackup.gather(from: core).encoded()
        }
        if categories.contains(.notes) { plan.notesDirectory = core.notesStore.notesDirectory }
        if categories.contains(.learning) {
            // From memory, not the files: the ranking store persists asynchronously.
            let encoder = BackupBundle.encoder
            plan.learning[.ranking] = try? encoder.encode(core.launcherRanking.visits)
            plan.learning[.emoji] = try? encoder.encode(core.frequentEmoji.records)
            plan.learning[.calculator] = try? encoder.encode(core.calcHistory.entries)
            plan.learningRecords =
                core.launcherRanking.visits.count + core.frequentEmoji.records.count
                + core.calcHistory.entries.count
        }
        return plan
    }

    nonisolated static func write(_ plan: Plan, into bundle: BackupBundle) throws -> Result {
        try bundle.prepare(plan.categories)
        var counts: [String: Int] = [:]

        if let settings = plan.settings {
            try bundle.write(settings, to: bundle.settingsURL)
            counts[BackupCategory.configuration.rawValue] = 1
        }
        if let directory = plan.notesDirectory {
            counts[BackupCategory.notes.rawValue] = try copyDocuments(
                from: directory, to: bundle.notesDirectory)
        }
        if !plan.learning.isEmpty {
            for (part, data) in plan.learning { try bundle.write(data, to: bundle.learningURL(part)) }
            counts[BackupCategory.learning.rawValue] = plan.learningRecords
        }

        let manifest = BackupManifest(
            appVersion: plan.appVersion, createdAt: Date(), counts: counts)
        try bundle.writeManifest(manifest)
        return Result(manifest: manifest)
    }

    // MARK: - Parts

    private nonisolated static func copyDocuments(
        from source: URL, to destination: URL
    ) throws
        -> Int
    {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: source.path)) ?? []
        var copied = 0
        for name in names.sorted() where (name as NSString).pathExtension == "md" {
            guard BackupBundle.isSafeName(name) else { continue }
            // Resolved: a symlinked note must travel as a file, since the reader refuses links.
            try FileManager.default.copyItem(
                at: source.appendingPathComponent(name).resolvingSymlinksInPath(),
                to: destination.appendingPathComponent(name))
            copied += 1
        }
        return copied
    }
}
