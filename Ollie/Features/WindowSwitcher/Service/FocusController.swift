import AppKit
import ApplicationServices

@MainActor
final class FocusController {
    private let diagnostics = Diagnostics(category: "window-switcher")
    private let worker = AXFocusWorker()
    private let spaceSwitcher = SwitcherSpaceController()

    func activate(
        _ item: SwitcherItem,
        refreshTarget: @MainActor (SwitcherItem) async -> SwitcherItem?
    ) async throws(CancellationError) -> SwitcherItem? {
        let benchmarkStart = diagnostics.isEnabled ? ContinuousClock.now : nil
        var attempts = 0
        var checks = 0
        var refreshes = 0
        if let window = item.windowElement,
           let windowID = await worker.windowID(for: AXWindowTarget(
               pid: item.runningApplication.processIdentifier, element: window
           )) {
            await spaceSwitcher.showWindow(windowID)
        }
        guard !Task.isCancelled else { throw CancellationError() }
        let previousPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let targetPID = item.runningApplication.processIdentifier
        var targetWasFrontmost = previousPID == targetPID
        var interrupted = false
        let canContinue: @MainActor () -> Bool = {
            guard !Task.isCancelled, !item.runningApplication.isTerminated else { return false }
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier == targetPID || SteamApplication.isSameApp(
                frontmostBundleID: frontmost?.bundleIdentifier,
                targetBundleID: item.runningApplication.bundleIdentifier
            ) {
                targetWasFrontmost = true
                return true
            }
            let mayContinue = !targetWasFrontmost && frontmost?.processIdentifier == previousPID
            if !mayContinue { interrupted = true }
            return mayContinue
        }
        let activated = await WindowActivation.perform(
            target: item,
            request: { target in
                attempts += 1
                await self.requestActivation(target, canContinue: canContinue)
            },
            isFocused: { target in
                checks += 1
                return await self.isFocused(target)
            },
            refreshTarget: { target in
                refreshes += 1
                return await refreshTarget(target)
            },
            canContinue: canContinue
        )
        if let benchmarkStart {
            diagnostics.benchmark(
                "focus.total", since: benchmarkStart,
                details: "pid=\(targetPID) kind=\(item.kind.benchmarkName) verified=\(activated != nil) cancelled=\(Task.isCancelled) attempts=\(attempts) checks=\(checks) refreshes=\(refreshes)"
            )
        }
        diagnostics.info("focus.verified pid=\(targetPID) success=\(activated != nil) cancelled=\(Task.isCancelled)")
        guard !Task.isCancelled, !interrupted else { throw CancellationError() }
        return activated
    }

    private func isFocused(_ item: SwitcherItem) async -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.processIdentifier == item.runningApplication.processIdentifier || SteamApplication.isSameApp(
            frontmostBundleID: frontmost?.bundleIdentifier,
            targetBundleID: item.runningApplication.bundleIdentifier
        ) else {
            return false
        }
        guard let targetWindow = item.windowElement else { return item.kind == .appOnly }
        return await worker.isFocused(AXWindowTarget(pid: item.runningApplication.processIdentifier, element: targetWindow))
    }

    private func requestActivation(_ item: SwitcherItem, canContinue: @MainActor () -> Bool) async {
        let benchmarkStart = ContinuousClock.now
        var unhideMilliseconds: Double?
        var appActivationMilliseconds: Double?
        var unminimizeMilliseconds: Double?
        var raiseMilliseconds: Double?
        var setMainMilliseconds: Double?
        var setFocusedMilliseconds: Double?
        var raiseResultCode: Int32?
        var mainResultCode: Int32?
        var focusedResultCode: Int32?
        defer {
            diagnostics.benchmark(
                "focus.request",
                since: benchmarkStart,
                details: "pid=\(item.runningApplication.processIdentifier) kind=\(item.kind.benchmarkName) minimized=\(item.isMinimized) unhide_ms=\(Self.benchmarkNumber(unhideMilliseconds)) app_activate_ms=\(Self.benchmarkNumber(appActivationMilliseconds)) minimized_read_ms=0.00 minimized_source=cached unminimize_ms=\(Self.benchmarkNumber(unminimizeMilliseconds)) raise_ms=\(Self.benchmarkNumber(raiseMilliseconds)) main_ms=\(Self.benchmarkNumber(setMainMilliseconds)) focused_ms=\(Self.benchmarkNumber(setFocusedMilliseconds)) raise_result=\(Self.benchmarkResult(raiseResultCode)) main_result=\(Self.benchmarkResult(mainResultCode)) focused_result=\(Self.benchmarkResult(focusedResultCode))"
            )
        }
        guard canContinue() else { return }
        let app = item.runningApplication
        diagnostics.info("focus.activate.begin app=\(item.appName) pid=\(app.processIdentifier) title=\(item.displayTitle)")
        if app.isHidden {
            let unhideStart = ContinuousClock.now
            let didUnhide = app.unhide()
            unhideMilliseconds = Diagnostics.elapsedMilliseconds(since: unhideStart)
            diagnostics.info("focus.unhide result=\(didUnhide)")
        }

        if let window = item.windowElement {
            let target = AXWindowTarget(pid: app.processIdentifier, element: window)
            if item.isMinimized {
                guard canContinue() else { return }
                let unminimizeStart = ContinuousClock.now
                let result = await worker.perform(.unminimize, target: target)
                unminimizeMilliseconds = Diagnostics.elapsedMilliseconds(since: unminimizeStart)
                diagnostics.info("focus.unminimize result=\(result.rawValue)")
            }
            guard canContinue() else { return }
            let mainStart = ContinuousClock.now
            let mainResult = await worker.perform(.makeMain, target: target)
            setMainMilliseconds = Diagnostics.elapsedMilliseconds(since: mainStart)
            mainResultCode = mainResult.rawValue
        }

        guard canContinue() else { return }
        let appActivationStart = ContinuousClock.now
        let activationApp = SteamApplication.isSteamHelper(app.bundleIdentifier)
            ? NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == SteamApplication.bundleID } ?? app
            : app
        let didActivate = await activateApplication(activationApp)
        appActivationMilliseconds = Diagnostics.elapsedMilliseconds(since: appActivationStart)
        diagnostics.info("focus.appActivate result=\(didActivate)")

        guard let window = item.windowElement else {
            diagnostics.info("focus.activate appOnly")
            return
        }

        let target = AXWindowTarget(pid: app.processIdentifier, element: window)

        guard canContinue() else { return }
        let raiseStart = ContinuousClock.now
        let raiseResult = await worker.perform(.raise, target: target)
        raiseMilliseconds = Diagnostics.elapsedMilliseconds(since: raiseStart)
        raiseResultCode = raiseResult.rawValue
        guard canContinue() else { return }
        let focusedStart = ContinuousClock.now
        let focusedResult = await worker.perform(.focus, target: target)
        setFocusedMilliseconds = Diagnostics.elapsedMilliseconds(since: focusedStart)
        focusedResultCode = focusedResult.rawValue
        diagnostics.info(
            "focus.windowActivate raise=\(raiseResult.rawValue) main=\(Self.benchmarkResult(mainResultCode)) focused=\(focusedResult.rawValue)"
        )
    }

    private func activateApplication(_ app: NSRunningApplication) async -> Bool {
        if app.isActive || app.activate(options: []) { return true }
        guard !Task.isCancelled, !app.isTerminated, let url = app.bundleURL else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        configuration.appleEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEActivate),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        do {
            let activated = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return !Task.isCancelled && activated.processIdentifier == app.processIdentifier
        } catch {
            diagnostics.warning("focus.workspaceActivate", details: "failed=\(error.localizedDescription)")
            return false
        }
    }

    private static func benchmarkNumber(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "na"
    }

    private static func benchmarkResult(_ value: Int32?) -> String {
        value.map(String.init) ?? "na"
    }

    func closeWindow(for item: SwitcherItem) async {
        diagnostics.info("focus.closeWindow app=\(item.appName) pid=\(item.runningApplication.processIdentifier) title=\(item.displayTitle)")
        let pid = item.runningApplication.processIdentifier
        let target = item.windowElement.map { AXWindowTarget(pid: pid, element: $0) }
        let result = await worker.closeWindow(pid: pid, target: target)
        diagnostics.info("focus.closeWindow pressResult=\(result.rawValue)")
    }

    func quitApp(for item: SwitcherItem) {
        let didTerminate = item.runningApplication.terminate()
        diagnostics.info("focus.quitApp app=\(item.appName) pid=\(item.runningApplication.processIdentifier) result=\(didTerminate)")
    }
}

private extension SwitcherItemKind {
    var benchmarkName: String {
        switch self {
        case .appOnly: "app_only"
        case .window: "window"
        }
    }
}
