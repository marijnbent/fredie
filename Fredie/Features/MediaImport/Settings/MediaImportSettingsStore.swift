import AppKit
import Foundation
import Observation

struct PreferredLocation: Codable, Equatable, Identifiable {
    let id: UUID
    var bookmark: Data
    var name: String
    var lastKnownPath: String

    init(url: URL) throws {
        id = UUID()
        bookmark = try url.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: [.volumeNameKey],
            relativeTo: nil
        )
        name = url.lastPathComponent
        lastKnownPath = url.path
    }

    func resolvedURL() -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

@MainActor
@Observable
final class MediaImportSettingsStore {
    private enum Key {
        static let preferredLocations = "Importie.PreferredLocations"
        static let openOnDetection = "Importie.OpenOnDetection"
    }

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var locationRevision = 0

    private(set) var preferredLocations: [PreferredLocation]
    var openOnDetection: Bool {
        didSet { defaults.set(openOnDetection, forKey: Key.openOnDetection) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.preferredLocations),
           let locations = try? JSONDecoder().decode([PreferredLocation].self, from: data) {
            preferredLocations = locations
        } else {
            preferredLocations = []
        }
        openOnDetection = (defaults.object(forKey: Key.openOnDetection) as? Bool) ?? true
    }

    var availableLocations: [(location: PreferredLocation, url: URL)] {
        _ = locationRevision
        return preferredLocations.compactMap { location in
            location.resolvedURL().map { (location, $0) }
        }
    }

    func adoptLocations(_ locations: [PreferredLocation]) {
        preferredLocations = locations
        saveLocations()
        refreshLocationAvailability()
    }

    func addPreferredLocation(_ url: URL) throws {
        if let existingIndex = preferredLocations.firstIndex(where: { $0.resolvedURL() == url }) {
            moveLocation(from: existingIndex, to: 0)
            return
        }
        preferredLocations.append(try PreferredLocation(url: url))
        saveLocations()
    }

    func removeLocations(at offsets: IndexSet) {
        preferredLocations.remove(atOffsets: offsets)
        saveLocations()
    }

    func moveLocations(from offsets: IndexSet, to destination: Int) {
        preferredLocations.move(fromOffsets: offsets, toOffset: destination)
        saveLocations()
    }

    func moveLocation(from source: Int, to destination: Int) {
        guard source != destination, preferredLocations.indices.contains(source) else { return }
        let location = preferredLocations.remove(at: source)
        preferredLocations.insert(location, at: min(destination, preferredLocations.count))
        saveLocations()
    }

    func refreshLocationAvailability() {
        locationRevision &+= 1
    }

    private func saveLocations() {
        if let data = try? JSONEncoder().encode(preferredLocations) {
            defaults.set(data, forKey: Key.preferredLocations)
        }
    }
}
