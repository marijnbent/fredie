import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let type: ClipboardItemType
    let timestamp: Date
    let sourceApp: String?
    let sourceBundleIdentifier: String?

    let textContent: String?

    let textFilename: String?

    let imageFilename: String?

    var ocrText: String?

    let isTruncated: Bool

    let originalSizeBytes: Int?

    init(id: UUID = UUID(), type: ClipboardItemType, timestamp: Date, sourceApp: String? = nil, sourceBundleIdentifier: String? = nil, textContent: String? = nil, textFilename: String? = nil, imageFilename: String? = nil, ocrText: String? = nil, isTruncated: Bool = false, originalSizeBytes: Int? = nil) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.sourceApp = sourceApp
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.textContent = textContent
        self.textFilename = textFilename
        self.imageFilename = imageFilename
        self.ocrText = ocrText
        self.isTruncated = isTruncated
        self.originalSizeBytes = originalSizeBytes
    }

    static func text(_ content: String, timestamp: Date, sourceApp: String? = nil, sourceBundleIdentifier: String? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            timestamp: timestamp,
            sourceApp: sourceApp,
            sourceBundleIdentifier: sourceBundleIdentifier,
            textContent: content
        )
    }

    static func image(filename: String, timestamp: Date, sourceApp: String? = nil, sourceBundleIdentifier: String? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .image,
            timestamp: timestamp,
            sourceApp: sourceApp,
            sourceBundleIdentifier: sourceBundleIdentifier,
            imageFilename: filename
        )
    }

    static func largeText(
        preview: String,
        timestamp: Date,
        filename: String,
        originalSizeBytes: Int,
        sourceApp: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            timestamp: timestamp,
            sourceApp: sourceApp,
            sourceBundleIdentifier: sourceBundleIdentifier,
            textContent: preview,
            textFilename: filename,
            originalSizeBytes: originalSizeBytes
        )
    }

    static func truncatedText(_ preview: String, timestamp: Date, originalSizeBytes: Int, sourceApp: String?, sourceBundleIdentifier: String? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            timestamp: timestamp,
            sourceApp: sourceApp,
            sourceBundleIdentifier: sourceBundleIdentifier,
            textContent: preview,
            isTruncated: true,
            originalSizeBytes: originalSizeBytes
        )
    }

    var isFileBacked: Bool {
        textFilename != nil
    }

    var previewText: String {
        guard type == .text else { return "Image" }
        var preview = ""
        var characterCount = 0
        var pendingSpace = false

        for character in textContent ?? "" {
            if character.isWhitespace {
                pendingSpace = characterCount > 0
                continue
            }
            if pendingSpace {
                guard characterCount < 50 else { return preview + "…" }
                preview.append(" ")
                characterCount += 1
                pendingSpace = false
            }
            guard characterCount < 50 else { return preview + "…" }
            preview.append(character)
            characterCount += 1
        }
        return preview
    }
}

enum ClipboardItemType: String, Codable, Equatable, Sendable {
    case text
    case image
}
