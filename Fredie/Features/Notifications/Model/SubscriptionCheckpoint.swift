import Foundation
import CryptoKit

struct SubscriptionCheckpoint: Codable, Sendable {
    private struct Entry: Codable, Sendable {
        let id: String
        let timestamp: Int64
    }

    private static let storageKey = "ollieNotificationCheckpoint"
    private static let maximumMessageCount = 512

    let topics: [String]
    private var entries: [Entry] = []
    private(set) var sinceTimestamp: Int64?

    init(topics: [String]) {
        self.topics = Self.identities(topics)
    }

    private static func identities(_ topics: [String]) -> [String] {
        topics.map { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() }.sorted()
    }

    var lastMessageID: String? {
        entries.last?.id
    }

    var recentMessageIDs: [String] {
        entries.map(\.id)
    }

    func contains(_ messageID: String) -> Bool {
        entries.contains { $0.id == messageID }
    }

    mutating func record(_ messageID: String, timestamp: Int64) {
        guard !contains(messageID) else { return }
        sinceTimestamp = min(sinceTimestamp ?? timestamp, timestamp)
        entries.append(Entry(id: messageID, timestamp: timestamp))
        if entries.count > Self.maximumMessageCount {
            entries.removeFirst(entries.count - Self.maximumMessageCount)
        }
    }

    mutating func finishReplay() {
        sinceTimestamp = entries.map(\.timestamp).min() ?? sinceTimestamp
    }

    static func load(topics: [String], from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: storageKey),
              let checkpoint = try? JSONDecoder().decode(Self.self, from: data),
              checkpoint.topics == Self.identities(topics)
        else {
            return Self(topics: topics)
        }
        return checkpoint
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
