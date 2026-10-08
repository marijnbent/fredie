import Foundation

enum LauncherAppResults {
    static func matches<Item>(
        _ items: [Item], query: LauncherOrder.Query, sensitivity: SearchSensitivity, limit: Int,
        isIncluded: (Item) -> Bool, key: (Item) -> String,
        profile: (Item) -> SearchProfile, signals: (Item) -> LauncherOrder.Signals
    ) -> [Item] {
        LauncherOrder.ranked(
            unique(items, isIncluded: isIncluded, key: key), query: query, sensitivity: sensitivity,
            limit: limit, profile: profile, signals: signals)
    }

    static func pinned<Item>(
        _ items: [Item], favoriteKeys: [String], fallbackLimit: Int,
        isIncluded: (Item) -> Bool, key: (Item) -> String, signals: (Item) -> LauncherOrder.Signals
    ) -> (items: [Item], pinnedCount: Int) {
        let candidates = unique(items, isIncluded: isIncluded, key: key)
        let byKey = Dictionary(candidates.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let favorites = favoriteKeys.compactMap { favoriteKey -> Item? in
            guard seen.insert(favoriteKey).inserted else { return nil }
            return byKey[favoriteKey]
        }
        guard favorites.isEmpty else { return (favorites, favorites.count) }
        let frequent = LauncherOrder.byUsage(candidates, signals: signals).prefix(max(fallbackLimit, 0))
        return (Array(frequent), 0)
    }

    private static func unique<Item>(
        _ items: [Item], isIncluded: (Item) -> Bool, key: (Item) -> String
    ) -> [Item] {
        var seen = Set<String>()
        return items.filter { isIncluded($0) && seen.insert(key($0)).inserted }
    }
}

struct LauncherAppGrid: Equatable, Sendable {
    let count: Int
    let columns: Int

    init(count: Int, columns: Int) {
        self.count = max(count, 0)
        self.columns = max(columns, 1)
    }

    func horizontal(from selection: Int, by delta: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(selection + delta, 0), count - 1)
    }

    func vertical(from selection: Int, by delta: Int) -> Int {
        guard count > 0 else { return 0 }
        let target = selection + delta * columns
        if target < 0 { return selection }
        if target >= count {
            return selection / columns < (count - 1) / columns ? count - 1 : selection
        }
        return target
    }
}
