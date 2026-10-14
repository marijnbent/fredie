import Foundation
import ImageCaptureCore

enum ImportStatus: Equatable, Sendable {
    case ready
    case importing
    case imported(URL)
    case failed(String)
}

final class CameraFileReference: @unchecked Sendable {
    let deviceID: String
    let deviceName: String
    let device: ICCameraDevice
    let file: ICCameraFile

    init(device: ICCameraDevice, file: ICCameraFile) {
        self.device = device
        self.file = file
        deviceID = device.persistentIDString ?? device.uuidString ?? device.name ?? "camera"
        deviceName = device.name ?? "Camera"
    }

    var id: String {
        "\(deviceID):\(file.fingerprint ?? file.name ?? UUID().uuidString)"
    }
}

enum MediaOrigin: @unchecked Sendable {
    case file(URL)
    case camera(CameraFileReference)
}

struct MediaClip: Identifiable, @unchecked Sendable {
    let id: String
    let origin: MediaOrigin
    let originalName: String
    let recordingDate: Date
    let duration: TimeInterval
    let fileSize: Int64
    let fingerprint: String
    var status: ImportStatus
    var companionOriginalURLs: [URL] = []
}

final class CameraSourceReference: @unchecked Sendable {
    let device: ICCameraDevice
    let files: [CameraFileReference]

    init(device: ICCameraDevice, files: [CameraFileReference]) {
        self.device = device
        self.files = files
    }
}

enum MediaSourceKind: @unchecked Sendable {
    case folder(URL)
    case camera(CameraSourceReference)
}

struct MediaSource: Identifiable, @unchecked Sendable {
    let id: String
    let name: String
    let kind: MediaSourceKind
}

struct FFprobeResult: Sendable {
    let duration: TimeInterval
    let creationDate: Date?
}

enum ImportieError: LocalizedError {
    case ffmpegMissing
    case noDestination
    case destinationUnavailable
    case noSelectedClips
    case sourceUnavailable(String)
    case processFailed(tool: String, message: String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing:
            "FFmpeg and FFprobe were not found. Install them with Homebrew: brew install ffmpeg"
        case .noDestination:
            "Add a preferred destination in Settings before importing."
        case .destinationUnavailable:
            "The selected destination is not connected or writable."
        case .noSelectedClips:
            "Select at least one video to import."
        case .sourceUnavailable(let name):
            "The source for \(name) is no longer available."
        case .processFailed(let tool, let message):
            "\(tool) failed: \(message)"
        case .invalidOutput(let name):
            "The converted file for \(name) could not be verified."
        }
    }
}
