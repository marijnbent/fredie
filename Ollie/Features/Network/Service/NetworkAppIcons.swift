import AppKit

@MainActor
final class NetworkAppIcons {
    private struct Key: Hashable {
        let id: String
        let path: String
    }
    private var cache: [Key: NSImage] = [:]

    func icon(for app: MonitoredApp) -> NSImage {
        let key = Key(id: app.id, path: app.path)
        if let icon = cache[key] { return icon }
        let icon = resolve(app)
        if cache.count > 512 { cache.removeAll() }
        cache[key] = icon
        return icon
    }

    private func resolve(_ app: MonitoredApp) -> NSImage {
        let workspace = NSWorkspace.shared
        if app.id.hasPrefix("bundle:") {
            if FileManager.default.fileExists(atPath: app.path) { return workspace.icon(forFile: app.path) }
            if let url = workspace.urlForApplication(withBundleIdentifier: String(app.id.dropFirst(7))) {
                return workspace.icon(forFile: url.path)
            }
        }
        if let tool = AppIdentity.tool(for: app), let icon = NSImage(named: tool.assetName) { return icon }
        let systemService = app.path.hasPrefix("/System/") || app.path.hasPrefix("/usr/libexec/") || app.path.hasPrefix("/Library/Apple/")
        return NSImage(systemSymbolName: systemService ? "gearshape.2" : app.id.hasPrefix("bundle:") ? "app.dashed" : "terminal", accessibilityDescription: app.name)!
    }
}
