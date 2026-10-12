import Foundation
import SQLite3

enum LegacyDataCopy {
    enum Failure: LocalizedError {
        case missing, existing, invalid
        var errorDescription: String? {
            switch self {
            case .missing: "No saved data found."
            case .existing: "Ollie already has data for this feature. Export or clear it before importing."
            case .invalid: "The saved data could not be safely imported."
            }
        }
    }

    static func copy(source: URL, destination: URL, kind: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw Failure.missing }
        guard try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw Failure.invalid }
        let historyName = kind == "clipboard" ? "history.json" : kind == "dictation" ? "transcript-history.json" : kind == "network" ? "usage.sqlite" : "ImportLedger.json"
        let existing = destination.appendingPathComponent(historyName)
        if fm.fileExists(atPath: existing.path) {
            guard kind != "network", let object = try? JSONSerialization.jsonObject(with: Data(contentsOf: existing)),
                  (object as? [Any])?.isEmpty == true || (object as? [String: Any])?.isEmpty == true else { throw Failure.existing }
        }
        if fm.fileExists(atPath: destination.path) {
            guard try destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw Failure.invalid }
            guard let children = fm.enumerator(at: destination, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { throw Failure.invalid }
            for case let child as URL in children {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw Failure.invalid }
                if values.isDirectory != true, child != existing { throw Failure.existing }
            }
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".adopt-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        if kind == "network" {
            try snapshotDatabase(source.appendingPathComponent(historyName), to: staging.appendingPathComponent(historyName))
        } else if kind == "clipboard" {
            try copyTree(source.appendingPathComponent(historyName), to: staging.appendingPathComponent(historyName))
            for name in ["images", "texts"] {
                let folder = source.appendingPathComponent(name)
                if fm.fileExists(atPath: folder.path) { try copyTree(folder, to: staging.appendingPathComponent(name)) }
            }
            let items = try ClipboardStorage(storageDirectory: staging).readHistory()
            for item in items {
                for (name, directory) in [(item.textFilename, "texts"), (item.imageFilename, "images")] {
                    guard let name else { continue }
                    guard fm.fileExists(atPath: staging.appendingPathComponent(directory).appendingPathComponent(name).path) else {
                        throw Failure.invalid
                    }
                }
            }
        } else if kind == "dictation" {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entries = try decoder.decode([TranscriptHistoryEntry].self, from: Data(contentsOf: source.appendingPathComponent(historyName)))
            var records = try JSONSerialization.jsonObject(with: Data(contentsOf: source.appendingPathComponent(historyName))) as? [[String: Any]]
            guard records?.count == entries.count else { throw Failure.invalid }
            let audio = staging.appendingPathComponent("Recordings")
            try fm.createDirectory(at: audio, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for (index, entry) in entries.enumerated() {
                guard let url = entry.rawRecordingFileURL else { continue }
                let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
                let supportAudio = source.appendingPathComponent("HistoryAudio").resolvingSymlinksInPath()
                let cacheAudio = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Talkie/HistoryAudio").resolvingSymlinksInPath()
                guard url.isFileURL, [supportAudio.path, cacheAudio.path].contains(canonical.deletingLastPathComponent().path) else { throw Failure.invalid }
                guard fm.fileExists(atPath: canonical.path) else {
                    records?[index].removeValue(forKey: "rawRecordingFileURL")
                    continue
                }
                guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                      try url.deletingLastPathComponent().resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw Failure.invalid }
                let name = entry.id.uuidString + "." + canonical.pathExtension
                try copyTree(canonical, to: audio.appendingPathComponent(name))
                records?[index]["rawRecordingFileURL"] = destination.appendingPathComponent("Recordings/" + name).absoluteString
            }
            let data = try JSONSerialization.data(withJSONObject: records ?? [], options: [.sortedKeys])
            _ = try decoder.decode([TranscriptHistoryEntry].self, from: data)
            try data.write(to: staging.appendingPathComponent(historyName), options: .atomic)
        } else {
            let ledger = source.appendingPathComponent(historyName)
            guard let _ = try JSONSerialization.jsonObject(with: Data(contentsOf: ledger)) as? [String: Any] else { throw Failure.invalid }
            try copyTree(ledger, to: staging.appendingPathComponent(historyName))
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.appendingPathComponent(historyName).path)
        let displaced = destination.deletingLastPathComponent().appendingPathComponent(".before-adopt-" + UUID().uuidString)
        let hadDestination = fm.fileExists(atPath: destination.path)
        if hadDestination { try fm.moveItem(at: destination, to: displaced) }
        do { try fm.moveItem(at: staging, to: destination) }
        catch {
            if hadDestination { try? fm.moveItem(at: displaced, to: destination) }
            throw error
        }
        if hadDestination { try? fm.removeItem(at: displaced) }
    }

    private static func copyTree(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
        guard values.isSymbolicLink != true else { throw Failure.invalid }
        if values.isDirectory == true {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                try copyTree(child, to: destination.appendingPathComponent(child.lastPathComponent))
            }
        } else {
            guard values.isRegularFile == true else { throw Failure.invalid }
            let before = try fm.attributesOfItem(atPath: source.path)
            try fm.copyItem(at: source, to: destination)
            let after = try fm.attributesOfItem(atPath: source.path)
            guard before[.modificationDate] as? Date == after[.modificationDate] as? Date,
                  before[.size] as? UInt64 == after[.size] as? UInt64 else { throw Failure.invalid }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
    }

    private static func snapshotDatabase(_ source: URL, to destination: URL) throws {
        var input: OpaquePointer?
        var output: OpaquePointer?
        defer { sqlite3_close(input); sqlite3_close(output) }
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open(destination.path, &output) == SQLITE_OK,
              let backup = sqlite3_backup_init(output, "main", input, "main") else { throw Failure.invalid }
        let result = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finish == SQLITE_OK else { throw Failure.invalid }
    }
}
