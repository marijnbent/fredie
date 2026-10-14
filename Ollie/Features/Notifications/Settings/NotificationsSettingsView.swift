import SwiftUI

struct NotificationsSettingsView: View {
    @Environment(NotificationsCoordinator.self) private var notifications
    @State private var topic = ""

    var body: some View {
        Form {
            Section("Delivery") {
                LabeledContent("Connection", value: notifications.connected ? "Connected" : "Disconnected")
                SettingsRow(title: "Notification banners") {
                    Button("Allow…") { Task { await notifications.requestPermission() } }
                }
            }
            Section("Topics") {
                HStack {
                    RevealableSecureField(title: "Topic name", text: $topic, prompt: Text("Topic name"))
                        .onSubmit(add)
                    Button("Add", action: add).disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(Array(notifications.topics.enumerated()), id: \.element) { index, value in
                    SettingsRow(title: "Topic \(index + 1)") {
                        SettingsRemoveButton(label: "Remove topic \(index + 1)") { notifications.remove(value) }
                    }
                }
                if let error = notifications.error { SettingsNotice(error) }
            }
            Section("Recent Notifications") {
                if notifications.messages.isEmpty {
                    Text("No notifications").foregroundStyle(.secondary)
                }
                ForEach(notifications.messages, id: \.id) { message in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(message.title ?? "Notification").font(.headline)
                        if let text = message.message { Text(text).textSelection(.enabled) }
                        if let date = message.time {
                            Text(Date(timeIntervalSince1970: date), style: .relative)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if message.bestURLString != nil {
                            Button("Open Link") { notifications.open(message) }
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
