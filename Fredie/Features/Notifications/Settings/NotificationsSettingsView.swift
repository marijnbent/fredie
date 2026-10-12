import SwiftUI

struct NotificationsSettingsView: View {
    @Environment(NotificationsCoordinator.self) private var notifications
    @Environment(AppSettings.self) private var settings
    @State private var topic = ""

    var body: some View {
        Form {
            Section {
                if settings.notificationsEnabled {
                    LabeledContent("Status", value: notifications.connected ? "Connected" : "Disconnected")
                }
                Button("Allow notification banners…") {
                    Task { await notifications.requestPermission() }
                }
            }
            Section("Topics") {
                HStack {
                    SecureField("Topic name", text: $topic)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(Array(notifications.topics.enumerated()), id: \.element) { index, value in
                    HStack {
                        Text("Topic \(index + 1)")
                        Spacer()
                        Button("Remove") { notifications.remove(value) }
                    }
                }
                if let error = notifications.error { Text(error).foregroundStyle(.red) }
            }
            Section("Recent") {
                if notifications.messages.isEmpty {
                    Text("No notifications").foregroundStyle(.secondary)
                }
                ForEach(notifications.messages, id: \.id) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.title ?? "Notification").font(.headline)
                        if let text = message.message { Text(text).textSelection(.enabled) }
                        if let date = message.time {
                            Text(Date(timeIntervalSince1970: date), style: .relative)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if message.bestURLString != nil {
                            Button("Open link") { notifications.open(message) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notifications)
        .onAppear { notifications.load(); notifications.markRead() }
        .onChange(of: notifications.unread) { _, _ in notifications.markRead() }
    }

    private func add() {
        notifications.add(topic)
        if notifications.error == nil { topic = "" }
    }
}
