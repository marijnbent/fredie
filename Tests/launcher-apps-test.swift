import Foundation

@main
struct LauncherAppsTest {
    struct Item {
        let name: String
        var isApp = true
        var key: String?
        var frecency: Double = 1
        var priority = 4

        var profile: SearchProfile { EntryNaming.profile(for: EntryNaming.Sources(name: name)) }

        var signals: LauncherOrder.Signals {
            LauncherOrder.Signals(
                alias: nil, usage: LauncherUsage(frecency: frecency, searchTerms: []),
                priority: priority, title: name)
        }
    }

    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool, _ detail: String = "") {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description) \(detail)")
                failures += 1
            }
        }

        func matches(_ query: String, _ items: [Item], limit: Int = 200) -> [String] {
            LauncherAppResults.matches(
                items, query: LauncherOrder.Query(query), sensitivity: .medium, limit: limit,
                isIncluded: \.isApp, key: { $0.key ?? $0.name }, profile: \.profile,
                signals: \.signals
            ).map(\.name)
        }

        func pinned(_ items: [Item], favorites: [String], fallback: Int = 12) -> ([String], Int) {
            let result = LauncherAppResults.pinned(
                items, favoriteKeys: favorites, fallbackLimit: fallback, isIncluded: \.isApp,
                key: { $0.key ?? $0.name }, signals: \.signals)
            return (result.items.map(\.name), result.pinnedCount)
        }

        let noise = (0..<50).map { Item(name: "Notes \($0)", isApp: false, frecency: 50, priority: 9) }
        let crowded = noise + [Item(name: "Notes App")]
        check(
            "an app survives a limit that non-apps would fill", matches("notes", crowded, limit: 5) == ["Notes App"],
            "got \(matches("notes", crowded, limit: 5))")
        check("non-apps never appear", !matches("notes", crowded).contains { $0.hasPrefix("Notes ") && $0 != "Notes App" })
        check("the limit still caps apps", matches("app", (0..<10).map { Item(name: "App \($0)") }, limit: 3).count == 3)

        let duplicated = [
            Item(name: "Safari", key: "com.apple.Safari"),
            Item(name: "Safari", key: "com.apple.Safari"),
            Item(name: "Safari Technology Preview", key: "com.apple.SafariTechnologyPreview"),
        ]
        check("one bundle appears once", matches("safari", duplicated).filter { $0 == "Safari" }.count == 1)
        check("distinct bundles both appear", matches("safari", duplicated).count == 2)
        check("an empty query lists nothing", matches("", duplicated).isEmpty)

        let frequent = [
            Item(name: "Mail", frecency: 2), Item(name: "Xcode", frecency: 40),
            Item(name: "Calendar", frecency: 10), Item(name: "Clipboard History", isApp: false, frecency: 99),
        ]
        let rivals = [Item(name: "Calendar", frecency: 2), Item(name: "Calculator", frecency: 40)]
        check(
            "frecency orders an app match", matches("cal", rivals) == ["Calculator", "Calendar"],
            "got \(matches("cal", rivals))")

        let favored = pinned(frequent, favorites: ["Calendar", "Mail", "Calendar", "Missing", "Clipboard History"])
        check("pins keep stored order", favored.0 == ["Calendar", "Mail"], "got \(favored.0)")
        check("pins count only apps", favored.1 == 2)

        let unpinned = pinned(frequent, favorites: [])
        check(
            "no pins falls back to most used apps", unpinned.0 == ["Xcode", "Calendar", "Mail"],
            "got \(unpinned.0)")
        check("a fallback is not pinned", unpinned.1 == 0)
        check("the fallback is capped", pinned(frequent, favorites: [], fallback: 2).0 == ["Xcode", "Calendar"])
        check("pins of hidden apps fall back too", pinned(frequent, favorites: ["Clipboard History"]).1 == 0)
        check("nothing to show is empty", pinned([], favorites: ["Mail"]).0.isEmpty)

        let grid = LauncherAppGrid(count: 10, columns: 4)
        check("right moves one tile", grid.horizontal(from: 1, by: 1) == 2)
        check("left stops at the first tile", grid.horizontal(from: 0, by: -1) == 0)
        check("right stops at the last tile", grid.horizontal(from: 9, by: 1) == 9)
        check("down moves one row", grid.vertical(from: 1, by: 1) == 5)
        check("up moves one row", grid.vertical(from: 6, by: -1) == 2)
        check("up from the first row stays", grid.vertical(from: 2, by: -1) == 2)
        check("down into a short last row lands on the last tile", grid.vertical(from: 7, by: 1) == 9)
        check("down from the last row stays", grid.vertical(from: 9, by: 1) == 9)
        check("an empty grid stays at zero", LauncherAppGrid(count: 0, columns: 4).vertical(from: 0, by: 1) == 0)
        check("zero columns acts as one", LauncherAppGrid(count: 3, columns: 0).vertical(from: 0, by: 1) == 1)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) failed")
        if failures > 0 { exit(1) }
    }
}
