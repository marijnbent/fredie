import Foundation

/// Staged bundle → live stores. Everything merges except Launcher Learning, which replaces.
@MainActor
enum BackupApplier {
    struct Summary: Sendable {
        var settings: SettingsBackup.ApplySummary?
        var notes = 0
        var learning = 0
        /// Reported rather than thrown: a failure here must not abort the categories after it.
        var problems: [String] = []
    }

    static func apply(
        _ categories: Set<BackupCategory>, from bundle: BackupBundle, to core: AppCore
    ) async -> Summary {
        var summary = Summary()
        if categories.contains(.configuration), let data = try? Data(contentsOf: bundle.settingsURL),
            let backup = try? SettingsBackup(json: data)
        {
            summary.settings = backup.apply(to: core)
        }
        if categories.contains(.notes) {
            summary.notes = await applyNotes(bundle, to: core)
        }
        if categories.contains(.learning) {
            summary.learning = applyLearning(bundle, to: core)
        }
        return summary
    }

    // MARK: - Parts

    private static func applyNotes(_ bundle: BackupBundle, to core: AppCore) async -> Int {
        let documents = bundle.documents(in: bundle.notesDirectory, extension: "md")
        guard !documents.isEmpty else { return 0 }
        return await core.notesStore.importNotes(
            documents.map {
                NotesRepository.Incoming(
                    title: ($0.name as NSString).deletingPathExtension, source: $0.contents)
            })
    }

    private static func applyLearning(_ bundle: BackupBundle, to core: AppCore) -> Int {
        var applied = 0
        if let visits = bundle.decodeLearning(.ranking, as: [String: LauncherVisit].self) {
            core.launcherRanking.replace(visits)
            applied += visits.count
        }
        if let records = bundle.decodeLearning(.emoji, as: [FrequentEmoji].self) {
            core.frequentEmoji.replace(records)
            applied += records.count
        }
        if let entries = bundle.decodeLearning(.calculator, as: [CalcHistoryEntry].self) {
            core.calcHistory.replace(entries)
            applied += entries.count
        }
        return applied
    }

}
