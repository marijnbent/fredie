import Foundation
import CryptoKit

struct PasteboardChangeTracker {
    private(set) var lastObservedChangeCount: Int
    private var selfWriteChangeCounts: Set<Int> = []

    init(currentChangeCount: Int) {
        lastObservedChangeCount = currentChangeCount
    }

    mutating func recordSelfWrite(changeCount: Int) {
        guard changeCount > lastObservedChangeCount else { return }
        selfWriteChangeCounts.insert(changeCount)
    }

    mutating func shouldCapture(changeCount: Int) -> Bool {
        guard changeCount != lastObservedChangeCount else { return false }

        lastObservedChangeCount = changeCount
        let isSelfWrite = selfWriteChangeCounts.remove(changeCount) != nil
        selfWriteChangeCounts = selfWriteChangeCounts.filter { $0 > changeCount }
        return !isSelfWrite
    }

    mutating func reset(changeCount: Int) {
        lastObservedChangeCount = changeCount
        selfWriteChangeCounts.removeAll()
    }
}

struct ClipboardContentSignature: Equatable, Sendable {
    private enum Kind: UInt8 {
        case text = 1
        case image = 2
    }

    private let digest: [UInt8]

    static func text(utf8Data: Data) -> ClipboardContentSignature {
        ClipboardContentSignature(kind: .text, data: utf8Data)
    }

    static func image(pngData: Data) -> ClipboardContentSignature {
        ClipboardContentSignature(kind: .image, data: pngData)
    }

    private init(kind: Kind, data: Data) {
        var hasher = SHA256()
        hasher.update(data: Data([kind.rawValue]))

        var byteCount = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &byteCount) { bytes in
            hasher.update(data: Data(bytes))
        }

        hasher.update(data: data)
        digest = Array(hasher.finalize())
    }
}

enum ClipboardImageData: Sendable {
    case png(Data)
    case tiff(Data)
}

enum ClipboardPayload: Sendable {
    case text(String)
    case image(ClipboardImageData)
}

struct ClipboardCapture: Sendable {
    let payload: ClipboardPayload
    let sourceApp: String?
    let sourceBundleIdentifier: String?
}
