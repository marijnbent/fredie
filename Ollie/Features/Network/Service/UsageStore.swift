import Foundation
import SQLite3

public final class UsageStore {
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public let url: URL

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("usage.sqlite")
        guard sqlite3_open(url.path, &database) == SQLITE_OK else { throw failure() }
        try execute("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=3000; CREATE TABLE IF NOT EXISTS apps (id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL); CREATE TABLE IF NOT EXISTS usage (day TEXT NOT NULL, app TEXT NOT NULL, received INTEGER NOT NULL, sent INTEGER NOT NULL, PRIMARY KEY(day, app)); CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value REAL NOT NULL);")
    }

    deinit { sqlite3_close(database) }

    public var startedAt: Date? {
        get throws {
            let stmt = try statement("SELECT value FROM metadata WHERE key='started'")
            defer { sqlite3_finalize(stmt) }
            return try step(stmt) ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)) : nil
        }
    }

    public func record(_ apps: [AppUsage], from start: Date, to end: Date, calendar: Calendar = .current) throws {
        guard end > start else { return }
        let parts = Self.intervals(from: start, to: end, calendar: calendar)
        try execute("BEGIN IMMEDIATE")
        do {
            let metadata = try statement("INSERT OR IGNORE INTO metadata VALUES('started', ?)")
            defer { sqlite3_finalize(metadata) }
            sqlite3_bind_double(metadata, 1, start.timeIntervalSince1970)
            try finish(metadata)
            let identity = try statement("INSERT INTO apps VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,path=excluded.path")
            let usage = try statement("INSERT INTO usage VALUES(?,?,?,?) ON CONFLICT(day,app) DO UPDATE SET received=received+excluded.received,sent=sent+excluded.sent")
            defer { sqlite3_finalize(identity); sqlite3_finalize(usage) }
            for app in apps where app.traffic.total > 0 {
                sqlite3_reset(identity)
                bind(app.id, to: identity, at: 1)
                bind(app.app.name, to: identity, at: 2)
                bind(app.app.path, to: identity, at: 3)
                try finish(identity)
                var remaining = app.traffic
                for (index, part) in parts.enumerated() {
                    let fraction = part.1 / end.timeIntervalSince(start)
                    let traffic = index == parts.count - 1 ? remaining : Traffic(
                        received: min(remaining.received, UInt64(Double(app.traffic.received) * fraction)),
                        sent: min(remaining.sent, UInt64(Double(app.traffic.sent) * fraction))
                    )
                    remaining.received -= traffic.received
                    remaining.sent -= traffic.sent
                    sqlite3_reset(usage)
                    bind(part.0, to: usage, at: 1)
                    bind(app.id, to: usage, at: 2)
                    sqlite3_bind_int64(usage, 3, Int64(clamping: traffic.received))
                    sqlite3_bind_int64(usage, 4, Int64(clamping: traffic.sent))
                    try finish(usage)
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func totals(from start: Date, through end: Date, calendar: Calendar = .current) throws -> [AppUsage] {
        let stmt = try statement("SELECT apps.id,apps.name,apps.path,SUM(usage.received),SUM(usage.sent) FROM usage JOIN apps ON apps.id=usage.app WHERE day>=? AND day<=? GROUP BY apps.id ORDER BY SUM(usage.received)+SUM(usage.sent) DESC,apps.name")
        defer { sqlite3_finalize(stmt) }
        bind(Self.dayKey(start, calendar: calendar), to: stmt, at: 1)
        bind(Self.dayKey(end, calendar: calendar), to: stmt, at: 2)
        var result: [AppUsage] = []
        while try step(stmt) {
            let app = MonitoredApp(id: text(stmt, at: 0), name: text(stmt, at: 1), path: text(stmt, at: 2))
            result.append(AppUsage(app: app, traffic: Traffic(received: UInt64(max(0, sqlite3_column_int64(stmt, 3))), sent: UInt64(max(0, sqlite3_column_int64(stmt, 4))))))
        }
        return AppIdentity.grouped(result)
    }

    public func days(from start: Date, through end: Date, appID: String? = nil, calendar: Calendar = .current) throws -> [DailyUsage] {
        let stmt = try statement("SELECT day,apps.id,apps.name,apps.path,SUM(received),SUM(sent) FROM usage JOIN apps ON apps.id=usage.app WHERE day>=? AND day<=? GROUP BY day,apps.id")
        defer { sqlite3_finalize(stmt) }
        bind(Self.dayKey(start, calendar: calendar), to: stmt, at: 1)
        bind(Self.dayKey(end, calendar: calendar), to: stmt, at: 2)
        var values: [String: Traffic] = [:]
        while try step(stmt) {
            let app = MonitoredApp(id: text(stmt, at: 1), name: text(stmt, at: 2), path: text(stmt, at: 3))
            guard appID == nil || AppIdentity.display(app).id == appID else { continue }
            let day = text(stmt, at: 0)
            let traffic = Traffic(received: UInt64(max(0, sqlite3_column_int64(stmt, 4))), sent: UInt64(max(0, sqlite3_column_int64(stmt, 5))))
            values[day] = (values[day] ?? Traffic()) + traffic
        }
        var day = calendar.startOfDay(for: start)
        var result: [DailyUsage] = []
        while day <= end {
            result.append(DailyUsage(date: day, traffic: values[Self.dayKey(day, calendar: calendar)] ?? Traffic()))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return result
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private static func intervals(from start: Date, to end: Date, calendar: Calendar) -> [(String, TimeInterval)] {
        var cursor = start
        var parts: [(String, TimeInterval)] = []
        while cursor < end {
            let boundary = min(end, calendar.dateInterval(of: .day, for: cursor)!.end)
            parts.append((dayKey(cursor, calendar: calendar), boundary.timeIntervalSince(cursor)))
            cursor = boundary
        }
        return parts
    }

    private func failure() -> NSError {
        NSError(domain: "Nettie.Storage", code: Int(sqlite3_errcode(database)), userInfo: [NSLocalizedDescriptionKey: "Usage history could not be saved or read: \(String(cString: sqlite3_errmsg(database)))"])
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw failure() }
        return stmt
    }
    private func bind(_ value: String, to stmt: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(stmt, index, value, -1, transient)
    }
    private func text(_ stmt: OpaquePointer, at index: Int32) -> String {
        String(cString: sqlite3_column_text(stmt, index))
    }
    private func finish(_ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    private func step(_ stmt: OpaquePointer) throws -> Bool {
        let code = sqlite3_step(stmt)
        guard code == SQLITE_ROW || code == SQLITE_DONE else { throw failure() }
        return code == SQLITE_ROW
    }
}
