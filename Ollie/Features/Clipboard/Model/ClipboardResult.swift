import Foundation

enum ClipboardResult: Identifiable, Equatable, Sendable {
    case item(ClipboardItem)
    case snippet(Snippet)

    var id: String {
        switch self {
        case .item(let item): "item-\(item.id)"
        case .snippet(let snippet): "snippet-\(snippet.id)"
        }
    }

    var text: String {
        switch self {
        case .item(let item): item.textContent ?? item.ocrText ?? ""
        case .snippet(let snippet): snippet.content
        }
    }
}
