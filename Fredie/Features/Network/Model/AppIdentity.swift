import Foundation

public enum ToolIdentity: String, CaseIterable, Sendable {
    case claude, codex, python, node, bun, deno, uv, git, curl, cloudflared, tailscale, onePassword, syncthing

    public var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .python: "Python"
        case .node: "Node.js"
        case .bun: "Bun"
        case .deno: "Deno"
        case .uv: "uv"
        case .git: "Git"
        case .curl: "curl"
        case .cloudflared: "Cloudflare Tunnel"
        case .tailscale: "Tailscale"
        case .onePassword: "1Password CLI"
        case .syncthing: "Syncthing"
        }
    }

    public var assetName: String { "Tool-\(rawValue)" }
}

public enum AppIdentity {
    public static func tool(for app: MonitoredApp) -> ToolIdentity? {
        if app.id.hasPrefix("tool:"), let tool = ToolIdentity(rawValue: String(app.id.dropFirst(5))) { return tool }
        guard !app.id.hasPrefix("bundle:") else { return nil }
        let components = app.path.split(separator: "/")
        let executable = components.last.map(String.init) ?? app.name
        if components.count >= 3, components[components.count - 3] == "claude", components[components.count - 2] == "versions",
           executable.wholeMatch(of: /\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?/) != nil { return .claude }
        if executable.wholeMatch(of: /python(?:\d+(?:\.\d+)*)?(?:t)?/) != nil { return .python }
        switch executable {
        case "claude": return .claude
        case "codex", "codex-aarch64-apple-darwin", "codex-x86_64-apple-darwin": return .codex
        case "node", "nodejs": return .node
        case "bun": return .bun
        case "deno": return .deno
        case "uv", "uvx": return .uv
        case "git", "git-remote-http", "git-remote-https": return .git
        case "curl": return .curl
        case "cloudflared": return .cloudflared
        case "tailscale", "tailscaled", "io.tailscale.ipn.macsys.network-extension", "io.tailscale.ipn.network-extension": return .tailscale
        case "op": return .onePassword
        case "syncthing": return .syncthing
        default: return nil
        }
    }

    public static func display(_ app: MonitoredApp) -> MonitoredApp {
        if let tool = tool(for: app) {
            return MonitoredApp(id: "tool:\(tool.rawValue)", name: tool.name, path: app.path)
        }
        guard !app.id.hasPrefix("bundle:"), !app.path.isEmpty else { return app }
        return MonitoredApp(id: app.id, name: URL(fileURLWithPath: app.path).lastPathComponent, path: app.path)
    }

    public static func grouped(_ rows: [AppUsage]) -> [AppUsage] {
        var result: [String: AppUsage] = [:]
        for row in rows {
            var app = display(row.app)
            if app.path.isEmpty, let previous = result[app.id]?.app { app = previous }
            result[app.id] = AppUsage(app: app, traffic: (result[app.id]?.traffic ?? Traffic()) + row.traffic)
        }
        return result.values.sorted {
            if $0.traffic.total != $1.traffic.total { return $0.traffic.total > $1.traffic.total }
            if $0.app.name != $1.app.name { return $0.app.name < $1.app.name }
            return $0.id < $1.id
        }
    }
}
