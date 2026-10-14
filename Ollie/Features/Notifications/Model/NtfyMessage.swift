import Foundation

struct NtfyMessage: Codable, Sendable {
    let id: String
    let event: String?
    let time: TimeInterval?
    let topic: String?
    let title: String?
    let message: String?
    let priority: Int?
    let click: String?
    let actions: [NtfyAction]?

    init(
        id: String,
        event: String?,
        time: TimeInterval? = nil,
        topic: String?,
        title: String?,
        message: String?,
        priority: Int?,
        click: String?,
        actions: [NtfyAction]?
    ) {
        self.id = id
        self.event = event
        self.time = time
        self.topic = topic
        self.title = title
        self.message = message
        self.priority = priority
        self.click = click
        self.actions = actions
    }

    var bestURLString: String? {
        if let click = cleanURL(click) {
            return click
        }

        return actions?.lazy.compactMap { cleanURL($0.url) }.first
    }

    private func cleanURL(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let trimmed,
            !trimmed.isEmpty,
            let url = URL(string: trimmed),
            ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
            return nil
        }
        return trimmed
    }
}

struct NtfyAction: Codable, Sendable {
    let action: String?
    let label: String?
    let url: String?
}
