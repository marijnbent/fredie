import Foundation
import OSLog

@MainActor
final class NtfySubscriber {
    typealias MessageHandler = @MainActor @Sendable (NtfyMessage) -> Bool
    typealias StateHandler = @MainActor @Sendable (Bool) -> Void

    private enum SubscriptionError: LocalizedError {
        case invalidURL
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Could not construct the ntfy subscription URL."
            case .invalidResponse:
                return "The ntfy server returned an invalid response."
            case .httpStatus(let statusCode):
                return "The ntfy server returned HTTP status \(statusCode)."
            }
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NtfyNotifier",
        category: "Subscription"
    )
    private static let maximumBackoffSeconds = 60.0
    private static let stableConnectionDuration = Duration.seconds(60)

    private let topics: [String]
    private let onMessage: MessageHandler
    private let onStateChanged: StateHandler
    private let decoder = JSONDecoder()
    private let defaults: UserDefaults
    private let session: URLSession
    private var checkpoint: SubscriptionCheckpoint

    private var task: Task<Void, Never>?
    private var isConnected = false

    init(
        topics: [String],
        defaults: UserDefaults = .standard,
        session: URLSession,
        onMessage: @escaping MessageHandler,
        onStateChanged: @escaping StateHandler
    ) {
        self.topics = topics
        self.defaults = defaults
        self.session = session
        self.checkpoint = SubscriptionCheckpoint(topics: topics)
        self.onMessage = onMessage
        self.onStateChanged = onStateChanged
    }

    func start() {
        guard task == nil, !topics.isEmpty else {
            return
        }

        checkpoint = SubscriptionCheckpoint.load(topics: topics, from: defaults)
        task = Task { [weak self] in
            await self?.listen()
        }
    }

    func stop() async {
        let activeTask = task
        activeTask?.cancel()
        await activeTask?.value
        task = nil
        session.invalidateAndCancel()
        setConnected(false)
    }

    static func subscriptionURL(for topics: [String], since timestamp: Int64? = nil) -> URL? {
        guard !topics.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "ntfy.sh"
        components.path = "/\(topics.joined(separator: ","))/json"
        if let timestamp {
            components.queryItems = [URLQueryItem(name: "since", value: String(timestamp))]
        }
        return components.url
    }

    private func listen() async {
        var consecutiveFailures = 0
        let clock = ContinuousClock()

        while !Task.isCancelled {
            var connectedAt: ContinuousClock.Instant?

            do {
                guard let url = Self.subscriptionURL(for: topics, since: checkpoint.sinceTimestamp) else {
                    throw SubscriptionError.invalidURL
                }

                let (bytes, response) = try await session.bytes(from: url)
                guard let response = response as? HTTPURLResponse else {
                    throw SubscriptionError.invalidResponse
                }
                guard (200..<300).contains(response.statusCode) else {
                    throw SubscriptionError.httpStatus(response.statusCode)
                }

                connectedAt = clock.now
                setConnected(true)

                for try await line in bytes.lines {
                    if Task.isCancelled {
                        break
                    }

                    guard
                        let data = line.data(using: .utf8),
                        let message = try? decoder.decode(NtfyMessage.self, from: data)
                    else {
                        continue
                    }

                    if message.event == "keepalive" {
                        checkpoint.finishReplay()
                        checkpoint.save(to: defaults)
                        continue
                    }
                    guard message.event == "message", !checkpoint.contains(message.id) else { continue }
                    if onMessage(message), let timestamp = message.time,
                       timestamp.isFinite, timestamp >= 0, timestamp < Double(Int64.max) {
                        checkpoint.record(message.id, timestamp: Int64(timestamp))
                        checkpoint.save(to: defaults)
                    }
                }
            } catch is CancellationError {
                break
            } catch {
                Self.logger.debug("Notification subscription disconnected")
            }

            setConnected(false)

            guard !Task.isCancelled else {
                break
            }

            if let connectedAt,
               connectedAt.duration(to: clock.now) >= Self.stableConnectionDuration {
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
            }

            let delay = Self.reconnectDelay(after: consecutiveFailures)
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                break
            }
        }

        setConnected(false)
    }

    private static func reconnectDelay(after failureCount: Int) -> Double {
        let exponent = min(max(failureCount - 1, 0), 6)
        let baseDelay = min(pow(2.0, Double(exponent)), maximumBackoffSeconds)
        let jitter = Double.random(in: 0.8...1.2)
        return min(baseDelay * jitter, maximumBackoffSeconds)
    }

    private func setConnected(_ connected: Bool) {
        guard connected != isConnected else {
            return
        }

        isConnected = connected
        onStateChanged(connected)
    }
}
