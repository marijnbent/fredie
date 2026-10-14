import Foundation

public struct Traffic: Equatable, Sendable, Codable {
    public var received: UInt64
    public var sent: UInt64
    public var total: UInt64 { received + sent }
    public init(received: UInt64 = 0, sent: UInt64 = 0) {
        self.received = received
        self.sent = sent
    }
    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(received: lhs.received + rhs.received, sent: lhs.sent + rhs.sent)
    }
}

public struct MonitoredApp: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let path: String
    public init(id: String, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

public struct AppUsage: Identifiable, Sendable {
    public var id: String { app.id }
    public let app: MonitoredApp
    public var traffic: Traffic
    public init(app: MonitoredApp, traffic: Traffic) {
        self.app = app
        self.traffic = traffic
    }
}

public enum UsagePeriod: Int, CaseIterable, Identifiable, Sendable {
    case today = 1, week = 7, month = 30
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        }
    }
    public func start(now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1 - rawValue, to: calendar.startOfDay(for: now))!
    }
}

public struct DailyUsage: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public var traffic: Traffic
}

public struct ProcessTraffic: Equatable, Sendable {
    public let pid: Int32
    public let name: String
    public let traffic: Traffic
}

public struct NetTopDecoder: Sendable {
    private var buffer = Data()
    private var rows: [ProcessTraffic] = []
    private var sampleDate: Date?
    public init() {}
    public mutating func append(_ data: Data, at date: Date) throws -> [(rows: [ProcessTraffic], date: Date)] {
        buffer.append(data)
        guard buffer.count < 4_000_000 else { throw MonitorError.invalidOutput }
        var frames: [(rows: [ProcessTraffic], date: Date)] = []
        while let end = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(...end)
            if line == ",bytes_in,bytes_out," || line == ",bytes_in,bytes_out" {
                if let sampleDate { frames.append((rows, sampleDate)) }
                sampleDate = date
                rows = []
            } else if sampleDate != nil && !line.isEmpty {
                var columns = line.split(separator: ",", omittingEmptySubsequences: false)
                if columns.last?.isEmpty == true { columns.removeLast() }
                let processName = columns.dropLast(2).joined(separator: ",")
                guard columns.count >= 3,
                      let dot = processName.lastIndex(of: "."),
                      let pid = Int32(processName[processName.index(after: dot)...]),
                      let received = Int64(columns[columns.count - 2]), let sent = Int64(columns[columns.count - 1]),
                      received <= Int64.max / 2, sent <= Int64.max / 2 else {
                    throw MonitorError.invalidOutput
                }
                rows.append(ProcessTraffic(pid: pid, name: String(processName[..<dot]), traffic: Traffic(received: UInt64(max(0, received)), sent: UInt64(max(0, sent)))))
            }
        }
        return frames
    }
}

public enum MonitorError: LocalizedError {
    case invalidOutput
    case stopped(String)
    public var errorDescription: String? {
        switch self {
        case .invalidOutput: "macOS returned an unreadable traffic sample. Restart monitoring to try again."
        case .stopped(let reason): "Monitoring stopped. \(reason)"
        }
    }
}
