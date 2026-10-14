import AppKit
import Foundation
import Observation
import OSLog

@MainActor @Observable
final class NetworkCoordinator {
    var period = UsagePeriod.today { didSet { reload() } }
    var day = Date() { didSet { reload() } }
    var selectedAppID: String? { didSet { reload() } }
    var apps: [AppUsage] = []
    var days: [DailyUsage] = []
    var rates: [String: Traffic] = [:]
    var error: String?
    var monitoring = false
    var startedAt: Date?
    var lastSample: Date?
    @ObservationIgnored private var store: UsageStore?
    @ObservationIgnored private let monitor = NetTopMonitor()
    @ObservationIgnored private let icons = NetworkAppIcons()
    @ObservationIgnored private var observers: [NotificationToken] = []
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var launchTime = Date()
    @ObservationIgnored private var currentDay = Calendar.current.startOfDay(for: Date())

    var rangeStart: Date { period == .today ? Calendar.current.startOfDay(for: day) : period.start(now: Date(), calendar: .current) }
    var rangeEnd: Date { period == .today ? day : Date() }
    var selectedApp: AppUsage? { apps.first { $0.id == selectedAppID } }
    var total: Traffic { selectedApp?.traffic ?? apps.reduce(Traffic()) { $0 + $1.traffic } }
    var rate: Traffic { selectedAppID.flatMap { rates[$0] } ?? (selectedAppID == nil ? rates.values.reduce(Traffic(), +) : Traffic()) }
    var status: String { error != nil ? "Monitoring stopped" : monitoring ? "Monitoring only" : watchdog == nil ? "Stopped" : "Starting…" }
    var directory: URL { AppPaths.applicationSupport().appendingPathComponent("Network", isDirectory: true) }

    init() {
        monitor.onSample = { [weak self] apps, start, end in self?.receive(apps, start: start, end: end) }
        monitor.onError = { [weak self] message in self?.fail(message) }
    }

    func start() {
        guard !enabled else { return }
        enabled = true
        generation += 1
        let revision = generation
        restart()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(NotificationToken(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.enabled, self.generation == revision else { return }
                self.suspend()
            }
        }, center: center))
        observers.append(NotificationToken(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.enabled, self.generation == revision else { return }
                self.restart()
            }
        }, center: center))
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard !Task.isCancelled, let self else { return }
                if self.error == nil && Date().timeIntervalSince(self.lastSample ?? self.launchTime) > 15 {
                    self.fail("No traffic samples received. Restart monitoring to try again.")
                }
            }
        }
    }

    func restart() {
        guard enabled else { return }
        monitor.stop()
        error = nil
        monitoring = false
        lastSample = nil
        launchTime = Date()
        do {
            if store == nil { store = try UsageStore(directory: directory) }
            startedAt = try store?.startedAt
            reload()
            guard error == nil else { return }
            monitor.start()
        } catch { fail(error.localizedDescription) }
    }

    func suspend() {
        monitor.stop()
        monitoring = false
        rates = [:]
    }

    private func fail(_ message: String) {
        guard enabled else { return }
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "nl.bentjes.fredie", category: "network").error("\(message, privacy: .public)")
        error = message
        suspend()
    }

    private func receive(_ samples: [AppUsage], start: Date, end: Date) {
        guard enabled else { return }
        do {
            try store?.record(samples, from: start, to: end)
            startedAt = try store?.startedAt
            let elapsed = end.timeIntervalSince(start)
            rates = Dictionary(uniqueKeysWithValues: AppIdentity.grouped(samples).map {
                ($0.id, Traffic(received: UInt64(Double($0.traffic.received) / elapsed), sent: UInt64(Double($0.traffic.sent) / elapsed)))
            })
            lastSample = end
            monitoring = true
            let today = Calendar.current.startOfDay(for: end)
            if today != currentDay {
                if Calendar.current.isDate(day, inSameDayAs: currentDay) { day = end }
                currentDay = today
            }
            reload()
        } catch { fail(error.localizedDescription) }
    }

    func reload() {
        guard let store else { return }
        do {
            apps = try store.totals(from: rangeStart, through: rangeEnd)
            if let selectedAppID, !apps.contains(where: { $0.id == selectedAppID }) { self.selectedAppID = nil }
            days = try store.days(from: rangeStart, through: rangeEnd, appID: selectedAppID)
        } catch { fail(error.localizedDescription) }
    }

    func icon(_ app: MonitoredApp) -> NSImage {
        icons.icon(for: app)
    }

    func stop() {
        enabled = false
        generation += 1
        watchdog?.cancel()
        watchdog = nil
        observers.removeAll()
        suspend()
        store = nil
    }

    static func bytes(_ value: UInt64) -> String {
        value == 0 ? "0 B" : ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .decimal)
    }
}
