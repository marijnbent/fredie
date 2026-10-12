import AppKit
import Foundation
@preconcurrency import ImageCaptureCore

private final class CameraDeviceBox: @unchecked Sendable {
    let device: ICCameraDevice

    init(_ device: ICCameraDevice) {
        self.device = device
    }
}

enum MediaDiscovery {
    static let supportedExtensions: Set<String> = ["mts", "m2ts", "mp4", "mov", "m4v"]

    static func isSupportedVideo(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func cameraMediaRoots(on volumeURL: URL) -> [URL] {
        let relativePaths = [
            "PRIVATE/AVCHD/BDMV/STREAM",
            "AVCHD/BDMV/STREAM",
            "MP_ROOT",
            "DCIM",
        ]
        let existingRoots = relativePaths
            .map { volumeURL.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        let rootVideos = (try? FileManager.default.contentsOfDirectory(
            at: volumeURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))?.contains(where: isSupportedVideo) == true
        return rootVideos ? [volumeURL] : existingRoots
    }

    static func videoFiles(in roots: [URL], stopAfterFirst: Bool = false) -> [URL] {
        var found = Set<URL>()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where isSupportedVideo(url) {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isRegularFile == true, values?.isHidden != true {
                    if stopAfterFirst { return [url] }
                    found.insert(url)
                }
            }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

@MainActor
final class MediaSourceMonitor: NSObject {
    var onSourceDetected: ((MediaSource) -> Void)?
    var onSourceRemoved: ((String) -> Void)?
    var onVolumesChanged: (() -> Void)?

    private let workspace = NSWorkspace.shared
    private let deviceBrowser = ICDeviceBrowser()
    private var cameraDevices: [String: ICCameraDevice] = [:]
    private var cameraCatalogTasks: [String: Task<Void, Never>] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        deviceBrowser.delegate = self
        deviceBrowser.browsedDeviceTypeMask = .camera
    }

    private var running = false

    func start() {
        guard !running else { return }
        running = true
        let center = workspace.notificationCenter
        workspaceObservers = [
            center.addObserver(
                forName: NSWorkspace.didMountNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
                Task { @MainActor in
                    self?.onVolumesChanged?()
                    self?.inspectMountedVolume(url)
                }
            },
            center.addObserver(
                forName: NSWorkspace.didUnmountNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
                Task { @MainActor in
                    self?.onVolumesChanged?()
                    self?.onSourceRemoved?("folder:\(url.path)")
                }
            },
            center.addObserver(
                forName: NSWorkspace.didRenameVolumeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.onVolumesChanged?() }
            },
        ]

        inspectMountedVolumes()
        deviceBrowser.start()
    }

    func stop() {
        running = false
        workspaceObservers.forEach(workspace.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        cameraCatalogTasks.values.forEach { $0.cancel() }
        cameraCatalogTasks.removeAll()
        for camera in cameraDevices.values where camera.hasOpenSession {
            camera.requestCloseSession(options: nil) { _ in }
        }
        cameraDevices.removeAll()
        deviceBrowser.stop()
    }

    func manualSource(for url: URL) -> MediaSource {
        MediaSource(id: "folder:\(url.path)", name: url.lastPathComponent, kind: .folder(url))
    }

    private func inspectMountedVolumes() {
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsEjectableKey]
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        for volume in volumes where volume.path.hasPrefix("/Volumes/") {
            inspectMountedVolume(volume)
        }
    }

    private func inspectMountedVolume(_ url: URL) {
        guard running else { return }
        let roots = MediaDiscovery.cameraMediaRoots(on: url)
        guard !roots.isEmpty, !MediaDiscovery.videoFiles(in: roots, stopAfterFirst: true).isEmpty else { return }
        onSourceDetected?(MediaSource(
            id: "folder:\(url.path)",
            name: url.lastPathComponent,
            kind: .folder(url)
        ))
    }

    private func inspectCamera(_ camera: ICCameraDevice, id: String) {
        let cameraBox = CameraDeviceBox(camera)
        camera.requestOpenSession(options: nil) { [weak self, cameraBox] error in
            guard error == nil else { return }
            Task { @MainActor in
                self?.waitForCameraCatalog(cameraBox.device, id: id)
            }
        }
    }

    private func waitForCameraCatalog(_ camera: ICCameraDevice, id: String) {
        cameraCatalogTasks[id]?.cancel()
        cameraCatalogTasks[id] = Task { [weak self, weak camera] in
            for _ in 0..<60 {
                guard !Task.isCancelled, let self, let camera else { return }
                let files = (camera.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
                let videos = files.filter { file in
                    guard let name = file.name else { return false }
                    return MediaDiscovery.supportedExtensions.contains(
                        URL(fileURLWithPath: name).pathExtension.lowercased()
                    )
                }
                if !videos.isEmpty || camera.contentCatalogPercentCompleted >= 100 {
                    guard !videos.isEmpty else { return }
                    let references = videos.map { CameraFileReference(device: camera, file: $0) }
                    self.onSourceDetected?(MediaSource(
                        id: id,
                        name: camera.name ?? "Camera",
                        kind: .camera(CameraSourceReference(device: camera, files: references))
                    ))
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

private struct ImportDeviceReference: @unchecked Sendable {
    let device: ICDevice
}

extension MediaSourceMonitor: ICDeviceBrowserDelegate {
    nonisolated func deviceBrowser(
        _ browser: ICDeviceBrowser,
        didAdd device: ICDevice,
        moreComing: Bool
    ) {
        let reference = ImportDeviceReference(device: device)
        Task { @MainActor [weak self] in
            let device = reference.device
            guard let camera = device as? ICCameraDevice else { return }
            guard let self, self.running else { return }
            if camera.mountPoint != nil { return }
            let id = "camera:\(camera.persistentIDString ?? camera.uuidString ?? camera.name ?? UUID().uuidString)"
            cameraDevices[id] = camera
            inspectCamera(camera, id: id)
        }
    }

    nonisolated func deviceBrowser(
        _ browser: ICDeviceBrowser,
        didRemove device: ICDevice,
        moreGoing: Bool
    ) {
        let reference = ImportDeviceReference(device: device)
        Task { @MainActor [weak self] in
            let device = reference.device
            guard let self, self.running else { return }
            let matching = cameraDevices.first { $0.value === device }
            guard let id = matching?.key else { return }
            cameraCatalogTasks[id]?.cancel()
            cameraCatalogTasks[id] = nil
            cameraDevices[id] = nil
            onSourceRemoved?(id)
        }
    }
}
