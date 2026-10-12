import AppKit
import ImageIO

final class ClipboardImageCache: @unchecked Sendable {
    private let imagesDirectory: URL
    private let thumbnails = NSCache<NSUUID, NSImage>()
    private let icons = NSCache<NSString, NSImage>()

    init(imagesDirectory: URL) {
        self.imagesDirectory = imagesDirectory
        thumbnails.totalCostLimit = 8 * 1024 * 1024
        thumbnails.countLimit = 512
        icons.countLimit = 128
    }

    func invalidateThumbnail(for id: UUID) { thumbnails.removeObject(forKey: id as NSUUID) }
    func removeAllThumbnails() { thumbnails.removeAllObjects() }

    @MainActor
    func thumbnail(for item: ClipboardItem) async -> NSImage? {
        guard let filename = item.imageFilename, !Task.isCancelled else { return nil }
        if let cached = thumbnails.object(forKey: item.id as NSUUID) { return cached }
        guard let url = try? ClipboardStorage.contentURL(filename, in: imagesDirectory) else { return nil }
        let image = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 56,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }.value
        guard !Task.isCancelled, let image else { return nil }
        let thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        thumbnails.setObject(thumbnail, forKey: item.id as NSUUID, cost: image.bytesPerRow * image.height)
        return thumbnail
    }

    @MainActor
    func sourceAppIcon(for item: ClipboardItem) async -> NSImage? {
        guard let identifier = item.sourceBundleIdentifier ?? item.sourceApp, !Task.isCancelled else { return nil }
        let key = identifier as NSString
        if let cached = icons.object(forKey: key) { return cached }
        let workspace = NSWorkspace.shared
        guard let url = item.sourceBundleIdentifier.flatMap({ workspace.urlForApplication(withBundleIdentifier: $0) })
            ?? workspace.runningApplications.first(where: { $0.localizedName == item.sourceApp })?.bundleURL else { return nil }
        let icon = workspace.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        icons.setObject(icon, forKey: key)
        return icon
    }
}
