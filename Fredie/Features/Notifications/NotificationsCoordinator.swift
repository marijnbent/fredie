import AppKit
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationsCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private struct Inbox: Codable {
        var messages: [NtfyMessage]
        var unread: Int
    }
    private(set) var topics: [String] = []
    private(set) var messages: [NtfyMessage] = []
    private(set) var unread = 0
    private(set) var connected = false
    private(set) var error: String?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var subscriber: NtfySubscriber?
    @ObservationIgnored private var transition: Task<Void, Never>?
    @ObservationIgnored private var deliveries: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let secrets = KeychainSecretStore(scope: "notification-topics")
    @ObservationIgnored private let account = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let inboxURL = AppPaths.applicationSupport().appendingPathComponent("notifications.json")

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    func load() {
        guard !loaded else { return }
        do {
            if let value = try secrets.secret(for: account), let data = value.data(using: .utf8) {
                topics = try JSONDecoder().decode([String].self, from: data)
            }
        } catch { self.error = "Could not read notification topics from Keychain."; return }
        do {
            if FileManager.default.fileExists(atPath: inboxURL.path) {
                let inbox = try JSONDecoder().decode(Inbox.self, from: Data(contentsOf: inboxURL))
                messages = Array(inbox.messages.prefix(100))
                unread = min(messages.count, max(0, inbox.unread))
            }
            loaded = true
            error = nil
        } catch { self.error = "Could not read the saved notification inbox." }
    }

    func apply() {
        generation += 1
        let revision = generation
        transition?.cancel()
        let previous = subscriber
        subscriber = nil
        connected = false
        transition = Task { [weak self] in
            await previous?.stop()
            guard !Task.isCancelled, let self, revision == generation, settings.notificationsEnabled else { return }
            load()
            guard loaded, !topics.isEmpty else { return }
            UNUserNotificationCenter.current().delegate = self
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 90
            let subscriber = NtfySubscriber(
                topics: topics, session: URLSession(configuration: configuration),
                onMessage: { [weak self] message in
                    guard let self, revision == self.generation, self.settings.notificationsEnabled else { return false }
                    return self.receive(message)
                },
                onStateChanged: { [weak self] value in
                    guard let self, revision == self.generation else { return }
                    self.connected = value
                })
            self.subscriber = subscriber
            subscriber.start()
        }
    }

    func add(_ topic: String) {
        let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty, topic.count <= 128,
              topic.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_-".unicodeScalars.contains($0) }) else {
            error = "Use a topic name containing letters, numbers, underscores or hyphens."
            return
        }
        load()
        guard loaded, !topics.contains(topic) else { return }
        save(topics + [topic])
    }

    func remove(_ topic: String) {
        save(topics.filter { $0 != topic })
    }

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if !granted { error = "Allow notifications in System Settings to show banners." }
        } catch { self.error = error.localizedDescription }
    }

    func markRead() {
        guard unread != 0, persist(messages: messages, unread: 0) else { return }
        unread = 0
    }

    func open(_ message: NtfyMessage) {
        guard let address = message.bestURLString, let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    func stop() async {
        generation += 1
        transition?.cancel()
        await transition?.value
        transition = nil
        await subscriber?.stop()
        subscriber = nil
        connected = false
        deliveries.values.forEach { $0.cancel() }
        deliveries.removeAll()
    }

    private func save(_ values: [String]) {
        do {
            let data = try JSONEncoder().encode(values)
            guard let value = String(data: data, encoding: .utf8) else { return }
            try secrets.setSecret(value, for: account)
            topics = values
            error = nil
            apply()
        } catch { self.error = "Could not save notification topics in Keychain." }
    }

    private func receive(_ message: NtfyMessage) -> Bool {
        guard !messages.contains(where: { $0.id == message.id }) else { return true }
        let saved = NtfyMessage(id: message.id, event: message.event, time: message.time,
            topic: nil, title: message.title, message: message.message, priority: message.priority,
            click: message.bestURLString, actions: nil)
        let next = Array(([saved] + messages).prefix(100))
        let nextUnread = min(100, unread + 1)
        guard persist(messages: next, unread: nextUnread) else { return false }
        messages = next
        unread = nextUnread
        let content = UNMutableNotificationContent()
        content.title = message.title ?? "Notification"
        content.body = message.message ?? ""
        content.sound = .default
        if let url = message.bestURLString { content.userInfo = ["url": url] }
        let request = UNNotificationRequest(identifier: "ollie.ntfy.\(message.id)", content: content, trigger: nil)
        deliveries[message.id] = Task { [weak self] in
            defer { self?.deliveries[message.id] = nil }
            do { try await UNUserNotificationCenter.current().add(request) }
            catch { self?.error = "Could not display a notification banner." }
        }
        return true
    }

    private func persist(messages: [NtfyMessage], unread: Int) -> Bool {
        do {
            try FileManager.default.createDirectory(at: inboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Inbox(messages: messages, unread: unread)).write(to: inboxURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: inboxURL.path)
            return true
        } catch {
            self.error = "Could not save the notification inbox."
            return false
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let address = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        _ = await MainActor.run { NSWorkspace.shared.open(url) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
