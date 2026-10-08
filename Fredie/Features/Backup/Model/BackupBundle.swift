import Foundation

/// The payload a `.fredie` seals; pure, so the harness drives the real layout.
struct BackupBundle: Sendable {
    enum LearningPart: String, CaseIterable, Sendable {
        case ranking
        case emoji
        case calculator
    }

    let root: URL

    init(root: URL) {
        self.root = root
    }

    // MARK: - Layout

    var manifestURL: URL { root.appendingPathComponent("manifest.json") }
    var settingsURL: URL { root.appendingPathComponent("settings.json") }

    private func directory(for category: BackupCategory) -> URL {
        let subpath = category.descriptor.subpath
        guard !subpath.isEmpty else { return root }
        return root.appendingPathComponent(subpath, isDirectory: true)
    }

    var notesDirectory: URL { directory(for: .notes) }

    func learningURL(_ part: LearningPart) -> URL {
        directory(for: .learning).appendingPathComponent("\(part.rawValue).json")
    }

    // MARK: - Writing

    /// Called once before composing; the archive carries no directory a category didn't ask for.
    func prepare(_ categories: Set<BackupCategory>) throws {
        try create(root)
        if categories.contains(.notes) { try create(notesDirectory) }
        if categories.contains(.learning) { try create(directory(for: .learning)) }
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func writeManifest(_ manifest: BackupManifest) throws {
        try write(try Self.encoder.encode(manifest), to: manifestURL)
    }

    func encode<Value: Encodable>(_ value: Value, to url: URL) throws {
        try write(try Self.encoder.encode(value), to: url)
    }

    /// Returns the name actually used; a duplicate or unsafe title is disambiguated, never dropped.
    @discardableResult
    func writeDocument(
        title: String, extension ext: String, contents: String, in directory: URL
    )
        throws -> String
    {
        let name = uniqueName(base: Self.sanitized(title), extension: ext, in: directory)
        try write(Data(contents.utf8), to: directory.appendingPathComponent(name))
        return name
    }

    // MARK: - Reading

    func readManifest() throws(BackupFormatError) -> BackupManifest {
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? Self.decoder.decode(BackupManifest.self, from: data)
        else { throw .unreadable }
        guard manifest.format == BackupManifest.currentFormat else {
            throw .unsupportedFormat(found: manifest.format)
        }
        return manifest
    }

    func documents(in directory: URL, extension ext: String) -> [(name: String, contents: String)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().compactMap { name in
            guard Self.isSafeName(name), (name as NSString).pathExtension == ext,
                let contents = try? String(
                    contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            else { return nil }
            return (name, contents)
        }
    }

    func decodeLearning<Value: Decodable>(_ part: LearningPart, as type: Value.Type) -> Value? {
        guard let data = try? Data(contentsOf: learningURL(part)) else { return nil }
        return try? Self.decoder.decode(Value.self, from: data)
    }

    // MARK: - Coding

    /// ISO-8601 dates, so a backup stays readable by eye and by anything but this decoder.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Names

    static func sanitized(_ title: String) -> String {
        let cleaned = title.components(separatedBy: Self.forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Leading dots hide the file and spell `..`; an empty result still needs a name.
        let trimmed = String(cleaned.drop { $0 == "." }.prefix(120))
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && name.rangeOfCharacter(from: Self.forbidden) == nil
    }

    private static let forbidden = CharacterSet(charactersIn: "/:\\\0")

    private func uniqueName(base: String, extension ext: String, in directory: URL) -> String {
        var candidate = "\(base).\(ext)"
        var suffix = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            suffix += 1
            candidate = "\(base) \(suffix).\(ext)"
        }
        return candidate
    }

    private func create(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
