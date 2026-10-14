import AppKit
import ApplicationServices

enum SteamApplication {
    static let bundleID = "com.valvesoftware.steam"
    static let helperBundleID = "com.valvesoftware.steam.helper"

    static func isSteamHelper(_ bundleID: String?) -> Bool {
        bundleID == helperBundleID
    }

    static func isSameApp(frontmostBundleID: String?, targetBundleID: String?) -> Bool {
        frontmostBundleID == bundleID && isSteamHelper(targetBundleID)
    }
}

enum WineApplication {
    static func wrapperURL(for app: NSRunningApplication) -> URL? {
        guard app.localizedName == "wine", app.bundleIdentifier == nil, let bundleURL = app.bundleURL else {
            return nil
        }
        return wrapperURL(forExecutable: bundleURL)
    }

    static func wrapperURL(forExecutable executableURL: URL) -> URL? {
        let marker = "/Contents/SharedSupport/wine/"
        let path = executableURL.standardizedFileURL.path
        guard let range = path.range(of: marker), path[..<range.lowerBound].hasSuffix(".app") else {
            return nil
        }
        return URL(fileURLWithPath: String(path[..<range.lowerBound]), isDirectory: true)
    }
}

struct WindowVisibilityInput {
    let isAppActive: Bool
    let isMinimized: Bool
    let isMain: Bool
    let isFocused: Bool
    let isFullScreen: Bool
    let windowMatch: CGWindowEntry?
}

struct WindowVisibilityResolver {
    static func visibility(
        for input: WindowVisibilityInput,
        settings: SwitcherSettings
    ) -> WindowVisibilityResult {
        if let windowMatch = input.windowMatch, windowMatch.isOnScreen {
            return WindowVisibilityResult(shouldInclude: true, sortGroup: .visibleWindow)
        }

        if settings.windowSource == .allSpaces {
            return WindowVisibilityResult(shouldInclude: true, sortGroup: .otherWindow)
        }

        if settings.windowSource == .visibleAndFullScreenSpaces && input.isFullScreen && !input.isMinimized {
            return WindowVisibilityResult(shouldInclude: true, sortGroup: .otherWindow)
        }

        if input.isAppActive && !input.isMinimized && (input.isFocused || input.isMain) {
            return WindowVisibilityResult(shouldInclude: true, sortGroup: .visibleWindow)
        }

        return WindowVisibilityResult(shouldInclude: false, sortGroup: .otherWindow)
    }
}

enum WindowDiscoverySortGroup: Int {
    case visibleWindow
    case otherWindow
    case appOnly
}

enum DiscoveryItemDestination: Equatable {
    case primary
    case bottom
    case excluded
}

struct DiscoveryItemPlacement {
    static func destinationForWindow(
        isHidden: Bool,
        isMinimized: Bool,
        settings: SwitcherSettings
    ) -> DiscoveryItemDestination {
        if isHidden && settings.hiddenMode == .doNotShow {
            return .excluded
        }

        if isMinimized && settings.minimizedMode == .doNotShow {
            return .excluded
        }

        if (isHidden && settings.hiddenMode == .showAtBottom) ||
            (isMinimized && settings.minimizedMode == .showAtBottom) {
            return .bottom
        }

        return .primary
    }

    static func destinationForAppOnly(settings: SwitcherSettings) -> DiscoveryItemDestination {
        switch settings.appsWithoutWindowsMode {
        case .show:
            return .primary
        case .showAtBottom:
            return .bottom
        case .doNotShow:
            return .excluded
        }
    }
}

struct WindowVisibilityResult {
    let shouldInclude: Bool
    let sortGroup: WindowDiscoverySortGroup
}

struct AXWindow: @unchecked Sendable {
    let element: AXUIElement
    let title: String?
    let frame: CGRect?
    let isMinimized: Bool
    let isMain: Bool
    let isFocused: Bool

    var sortPriority: Int {
        (isFocused ? 2 : 0) + (isMain ? 1 : 0)
    }

    func hasSameTitleAndFrame(as other: AXWindow) -> Bool {
        guard let title, !title.isEmpty, title == other.title,
              let frame, let otherFrame = other.frame else {
            return false
        }
        return WindowOrdering.framesMatch(frame, otherFrame)
    }

    func updatingFocus(focused: AXUIElement?, main: AXUIElement?) -> AXWindow {
        updatingFocus(
            isFocused: focused.map { CFEqual(element, $0) } ?? isFocused,
            isMain: main.map { CFEqual(element, $0) } ?? isMain
        )
    }

    func updatingFocus(isFocused: Bool, isMain: Bool) -> AXWindow {
        AXWindow(
            element: element,
            title: title,
            frame: frame,
            isMinimized: isMinimized,
            isMain: isMain,
            isFocused: isFocused
        )
    }

    static func preferredIndex(in windows: [AXWindow]) -> Int? {
        windows.firstIndex(where: \.isFocused)
            ?? windows.firstIndex(where: \.isMain)
            ?? (windows.count == 1 ? 0 : nil)
    }

    static func merging(_ existing: [AXWindow], with partial: [AXWindow]) -> [AXWindow] {
        let focused = partial.first(where: \.isFocused)?.element
        let main = partial.first(where: \.isMain)?.element
        var merged = existing.map { $0.updatingFocus(focused: focused, main: main) }
        for window in partial {
            if let index = merged.firstIndex(where: { CFEqual($0.element, window.element) }) {
                merged[index] = window
            } else {
                merged.append(window)
            }
        }
        return merged
    }
}

struct WindowReplacement {
    let previous: AXUIElement
    let current: AXWindow

    static func unambiguous(previous: [AXWindow], current: [AXWindow]) -> [WindowReplacement] {
        let removed = previous.filter { old in !current.contains { CFEqual(old.element, $0.element) } }
        let added = current.filter { new in !previous.contains { CFEqual(new.element, $0.element) } }
        return removed.compactMap { old in
            let candidates = added.filter { old.hasSameTitleAndFrame(as: $0) }
            guard candidates.count == 1, let replacement = candidates.first,
                  previous.filter({ $0.hasSameTitleAndFrame(as: replacement) }).count == 1,
                  current.filter({ $0.hasSameTitleAndFrame(as: old) }).count == 1 else {
                return nil
            }
            return WindowReplacement(previous: old.element, current: replacement)
        }
    }
}

enum AXWindowReadResult: @unchecked Sendable {
    case window(AXWindow)
    case unknownWindow(AXWindow)
    case ignored
    case failure(AXError)
}

struct AXWindowReader: AXWindowReading {
    static let defaultMessagingTimeout: Float = 0.08

    let messagingTimeout: Float

    init(messagingTimeout: Float = Self.defaultMessagingTimeout) {
        self.messagingTimeout = messagingTimeout
    }

    private static let batchedAttributeKeys: [String] = [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXTitleAttribute,
        kAXPositionAttribute,
        kAXSizeAttribute,
        kAXMinimizedAttribute,
        kAXMainAttribute,
        kAXFocusedAttribute,
    ]
    private static let allowedWindowSubroles: Set<String> = [
        kAXStandardWindowSubrole as String,
        kAXDialogSubrole as String,
    ]

    func prepareForSnapshot(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
    }

    func applicationWindows(pid: pid_t) -> AXApplicationWindows {
        let app = AXUIElementCreateApplication(pid)
        prepareForSnapshot(app)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        return AXApplicationWindows(elements: value as? [AXUIElement] ?? [], result: result)
    }

    func applicationFocus(pid: pid_t) -> AXApplicationFocus {
        let app = AXUIElementCreateApplication(pid)
        prepareForSnapshot(app)
        let focused = windowAttributeResult(kAXFocusedWindowAttribute, on: app)
        let main = windowAttributeResult(kAXMainWindowAttribute, on: app)
        return AXApplicationFocus(
            focused: focused.value, main: main.value,
            isComplete: (focused.result == .success || focused.result == .noValue)
                && (main.result == .success || main.result == .noValue)
        )
    }

    func window(from element: AXUIElement) -> AXWindow? {
        guard case .window(let window) = readWindow(from: element) else {
            return nil
        }
        return window
    }

    func readWindow(from element: AXUIElement) -> AXWindowReadResult {
        prepareForSnapshot(element)
        let batch = batchedAttributes(for: element)
        if batch.result.shouldRetry {
            return .failure(batch.result)
        }

        var role = batch.attributes.string(kAXRoleAttribute)
        if role == nil {
            let read = stringAttributeResult(kAXRoleAttribute, on: element)
            if read.result.shouldRetry {
                return .failure(read.result)
            }
            role = read.value
        }

        var subrole = batch.attributes.string(kAXSubroleAttribute)
        if subrole == nil {
            let read = stringAttributeResult(kAXSubroleAttribute, on: element)
            if read.result.shouldRetry {
                return .failure(read.result)
            }
            subrole = read.value
        }

        guard role == (kAXWindowRole as String), let subrole,
              Self.allowedWindowSubroles.contains(subrole) || subrole == "AXUnknown" else {
            return .ignored
        }
        if isWindowSharingControl(element, subrole: subrole) {
            return .ignored
        }

        let window = AXWindow(
            element: element,
            title: batch.attributes.string(kAXTitleAttribute) ?? stringAttribute(kAXTitleAttribute, on: element),
            frame: batch.attributes.frame() ?? frame(for: element),
            isMinimized: batch.attributes.bool(kAXMinimizedAttribute) ?? boolAttribute(kAXMinimizedAttribute, on: element) ?? false,
            isMain: batch.attributes.bool(kAXMainAttribute) ?? boolAttribute(kAXMainAttribute, on: element) ?? false,
            isFocused: batch.attributes.bool(kAXFocusedAttribute) ?? boolAttribute(kAXFocusedAttribute, on: element) ?? false
        )
        return subrole == "AXUnknown" ? .unknownWindow(window) : .window(window)
    }

    func isWindowSharingControl(
        _ element: AXUIElement,
        subrole: String,
        readAttribute: (AXUIElement, String) -> CFTypeRef? = { element, key in
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else {
                return nil
            }
            return value
        }
    ) -> Bool {
        guard subrole == (kAXDialogSubrole as String),
              let children = readAttribute(element, kAXChildrenAttribute) as? [AXUIElement],
              children.count == 1,
              let child = children.first else {
            return false
        }
        prepareForSnapshot(child)
        return readAttribute(child, kAXRoleAttribute) as? String == (kAXButtonRole as String)
            && readAttribute(child, kAXTitleAttribute) as? String == "WindowSharingSessionButton"
    }

    private func batchedAttributes(for element: AXUIElement) -> BatchedAXAttributeResult {
        var values: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(
            element,
            Self.batchedAttributeKeys as CFArray,
            [],
            &values
        )
        guard
            result == .success,
            let rawValues = values as? [Any],
            rawValues.count == Self.batchedAttributeKeys.count
        else {
            return BatchedAXAttributeResult(attributes: BatchedAXAttributes(valuesByKey: [:]), result: result)
        }

        let pairs = zip(Self.batchedAttributeKeys, rawValues).compactMap { key, value -> (String, Any)? in
            guard !(value is NSNull) else {
                return nil
            }
            return (key, value)
        }
        return BatchedAXAttributeResult(
            attributes: BatchedAXAttributes(valuesByKey: Dictionary(uniqueKeysWithValues: pairs)),
            result: result
        )
    }

    func frame(for window: AXUIElement) -> CGRect? {
        guard
            let origin = pointAttribute(kAXPositionAttribute, on: window),
            let size = sizeAttribute(kAXSizeAttribute, on: window)
        else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    func stringAttribute(_ key: String, on element: AXUIElement) -> String? {
        stringAttributeResult(key, on: element).value
    }

    private func stringAttributeResult(_ key: String, on element: AXUIElement) -> (value: String?, result: AXError) {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success else {
            return (nil, result)
        }
        return (value as? String, result)
    }

    func pointAttribute(_ key: String, on element: AXUIElement) -> CGPoint? {
        axValueAttribute(key, type: .cgPoint, on: element)
    }

    func sizeAttribute(_ key: String, on element: AXUIElement) -> CGSize? {
        axValueAttribute(key, type: .cgSize, on: element)
    }

    func boolAttribute(_ key: String, on element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success, let number = value as? NSNumber else {
            return nil
        }
        return number.boolValue
    }

    func windowAttribute(_ key: String, on element: AXUIElement) -> AXUIElement? {
        windowAttributeResult(key, on: element).value
    }

    private func windowAttributeResult(_ key: String, on element: AXUIElement) -> (value: AXUIElement?, result: AXError) {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return (nil, result == .success ? .failure : result)
        }
        return (unsafeDowncast(value, to: AXUIElement.self), result)
    }

    private func axValueAttribute<T>(_ key: String, type: AXValueType, on element: AXUIElement) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard
            result == .success,
            let axValue = value,
            CFGetTypeID(axValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let typedValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(typedValue) == type else {
            return nil
        }

        switch type {
        case .cgPoint:
            var point = CGPoint.zero
            guard AXValueGetValue(typedValue, .cgPoint, &point) else {
                return nil
            }
            return point as? T
        case .cgSize:
            var size = CGSize.zero
            guard AXValueGetValue(typedValue, .cgSize, &size) else {
                return nil
            }
            return size as? T
        default:
            return nil
        }
    }

    private struct BatchedAXAttributes {
        let valuesByKey: [String: Any]

        func string(_ key: String) -> String? {
            valuesByKey[key] as? String
        }

        func bool(_ key: String) -> Bool? {
            (valuesByKey[key] as? NSNumber)?.boolValue
        }

        func frame() -> CGRect? {
            guard
                let origin: CGPoint = axValue(kAXPositionAttribute, type: .cgPoint),
                let size: CGSize = axValue(kAXSizeAttribute, type: .cgSize)
            else {
                return nil
            }
            return CGRect(origin: origin, size: size)
        }

        private func axValue<T>(_ key: String, type: AXValueType) -> T? {
            guard
                let value = valuesByKey[key] as CFTypeRef?,
                CFGetTypeID(value) == AXValueGetTypeID()
            else {
                return nil
            }

            let axValue = unsafeDowncast(value, to: AXValue.self)
            guard AXValueGetType(axValue) == type else {
                return nil
            }

            switch type {
            case .cgPoint:
                var point = CGPoint.zero
                guard AXValueGetValue(axValue, .cgPoint, &point) else {
                    return nil
                }
                return point as? T
            case .cgSize:
                var size = CGSize.zero
                guard AXValueGetValue(axValue, .cgSize, &size) else {
                    return nil
                }
                return size as? T
            default:
                return nil
            }
        }
    }

    private struct BatchedAXAttributeResult {
        let attributes: BatchedAXAttributes
        let result: AXError
    }
}

extension AXError {
    var isCompleteWindowRead: Bool {
        self == .success || self == .noValue || self == .attributeUnsupported
    }

    var shouldRetry: Bool {
        switch self {
        case .cannotComplete, .failure, .invalidUIElement, .apiDisabled:
            return true
        default:
            return false
        }
    }
}

struct CGWindowEntry: Sendable, Equatable {
    let order: Int
    let pid: pid_t
    let title: String?
    let bounds: CGRect
    let layer: Int
    let isOnScreen: Bool
}

struct WindowActivationRecord {
    let pid: pid_t
    let element: AXUIElement
    let title: String?
    let frame: CGRect?
    let order: Int

    func matches(_ window: AXWindow) -> Bool {
        CFEqual(element, window.element)
    }

    func replacingWindow(using replacements: [WindowReplacement]) -> WindowActivationRecord {
        guard let replacement = replacements.first(where: { CFEqual(element, $0.previous) }) else {
            return self
        }
        return WindowActivationRecord(
            pid: pid, element: replacement.current.element, title: replacement.current.title,
            frame: replacement.current.frame, order: order
        )
    }
}

struct WindowActivationHistory {
    private var confirmedRecords: [WindowActivationRecord] = []

    var records: [WindowActivationRecord] {
        confirmedRecords.filter { record in
            guard let pending = pendingWindows[record.pid] else { return true }
            return !CFEqual(record.element, pending.element)
        } + pendingWindows.values
    }

    private var appOrders: [pid_t: Int] = [:]
    private var lastObservedWindows: [pid_t: WindowActivationRecord] = [:]
    private var pendingApplicationOrders: [pid_t: Int] = [:]
    private var pendingWindows: [pid_t: WindowActivationRecord] = [:]
    private var counter = 0

    func appOrder(for pid: pid_t) -> Int {
        pendingWindows[pid]?.order ?? appOrders[pid] ?? 0
    }

    func windowOrder(pid: pid_t, window: AXWindow) -> Int {
        records
            .filter { $0.pid == pid && $0.matches(window) }
            .map(\.order)
            .max() ?? 0
    }

    mutating func recordApplicationActivation(pid: pid_t) {
        pendingApplicationOrders = pendingApplicationOrders.filter { $0.key == pid }
        pendingWindows = pendingWindows.filter { $0.key == pid }

        guard pendingApplicationOrders[pid] == nil, pendingWindows[pid] == nil else {
            return
        }

        let order = nextOrder()
        appOrders[pid] = order
        pendingApplicationOrders[pid] = order
    }

    @discardableResult
    mutating func recordExplicitActivation(pid: pid_t, window: AXWindow) -> Int {
        pendingApplicationOrders.removeAll()
        pendingWindows.removeAll()

        let order = nextOrder()
        pendingWindows[pid] = WindowActivationRecord(
            pid: pid, element: window.element, title: window.title, frame: window.frame, order: order
        )
        return order
    }

    mutating func cancelActivation(pid: pid_t, order: Int) {
        if pendingWindows[pid]?.order == order {
            pendingWindows.removeValue(forKey: pid)
        }
    }

    mutating func observeFocus(pid: pid_t, window: AXWindow) {
        if let pendingWindow = pendingWindows[pid] {
            if pendingWindow.matches(window) {
                lastObservedWindows[pid] = store(pid: pid, window: window, order: pendingWindow.order)
                appOrders[pid] = pendingWindow.order
                pendingWindows.removeValue(forKey: pid)
                return
            }

            if let observedWindow = lastObservedWindows[pid], observedWindow.matches(window) {
                lastObservedWindows[pid] = store(pid: pid, window: window, order: observedWindow.order)
                return
            }

            pendingWindows.removeValue(forKey: pid)
        }

        if let order = pendingApplicationOrders.removeValue(forKey: pid) {
            lastObservedWindows[pid] = store(pid: pid, window: window, order: order)
            return
        }

        if let observedWindow = lastObservedWindows[pid], observedWindow.matches(window) {
            lastObservedWindows[pid] = store(pid: pid, window: window, order: observedWindow.order)
            return
        }

        let order = nextOrder()
        appOrders[pid] = order
        lastObservedWindows[pid] = store(pid: pid, window: window, order: order)
    }

    mutating func remove(pid: pid_t, element: AXUIElement) {
        removeRecords { $0.pid == pid && CFEqual($0.element, element) }
    }

    mutating func reconcile(pid: pid_t, previous: [AXWindow], current windows: [AXWindow]) {
        let replacements = WindowReplacement.unambiguous(previous: previous, current: windows)
        confirmedRecords = confirmedRecords.map { $0.pid == pid ? $0.replacingWindow(using: replacements) : $0 }
        lastObservedWindows[pid] = lastObservedWindows[pid]?.replacingWindow(using: replacements)
        pendingWindows[pid] = pendingWindows[pid]?.replacingWindow(using: replacements)
        removeRecords { record in
            record.pid == pid && !windows.contains(where: record.matches)
        }
    }

    private mutating func removeRecords(where shouldRemove: (WindowActivationRecord) -> Bool) {
        confirmedRecords.removeAll(where: shouldRemove)
        lastObservedWindows = lastObservedWindows.filter { !shouldRemove($0.value) }
        pendingWindows = pendingWindows.filter { !shouldRemove($0.value) }
    }

    mutating func prune(keeping pids: Set<pid_t>) {
        confirmedRecords.removeAll { !pids.contains($0.pid) }
        appOrders = appOrders.filter { pids.contains($0.key) }
        lastObservedWindows = lastObservedWindows.filter { pids.contains($0.key) }
        pendingApplicationOrders = pendingApplicationOrders.filter { pids.contains($0.key) }
        pendingWindows = pendingWindows.filter { pids.contains($0.key) }
    }

    private mutating func nextOrder() -> Int {
        counter += 1
        return counter
    }

    private mutating func store(pid: pid_t, window: AXWindow, order: Int) -> WindowActivationRecord {
        confirmedRecords.removeAll { $0.pid == pid && $0.matches(window) }
        let record = WindowActivationRecord(
            pid: pid,
            element: window.element,
            title: window.title,
            frame: window.frame,
            order: order
        )
        confirmedRecords.append(record)
        return record
    }
}

extension Array where Element == AXUIElement {
    @discardableResult
    mutating func appendIfMissing(_ element: AXUIElement) -> Bool {
        guard !contains(where: { CFEqual($0, element) }) else {
            return false
        }

        append(element)
        return true
    }
}

struct WindowOrdering {
    private static let frameTolerance: CGFloat = 2
    private let entriesByPID: [pid_t: [CGWindowEntry]]

    init(entries: [CGWindowEntry]) {
        let filteredEntries = entries.filter { $0.layer == 0 }
        self.entriesByPID = Dictionary(grouping: filteredEntries, by: \.pid)
    }

    func matches(pid: pid_t, windows: [AXWindow]) -> [CGWindowEntry?] {
        let entries = entriesByPID[pid, default: []]
        var matches = [CGWindowEntry?](repeating: nil, count: windows.count)
        var candidates = windows.enumerated().flatMap { windowIndex, window in
            entries.enumerated().compactMap { entryIndex, entry -> WindowMatchCandidate? in
                guard let score = score(entry: entry, for: window) else { return nil }
                return WindowMatchCandidate(windowIndex: windowIndex, entryIndex: entryIndex, score: score)
            }
        }

        while !candidates.isEmpty {
            let byWindow = Dictionary(grouping: candidates, by: \.windowIndex)
            let byEntry = Dictionary(grouping: candidates, by: \.entryIndex)
            let resolved = candidates.filter { candidate in
                let windowCandidates = byWindow[candidate.windowIndex, default: []]
                let entryCandidates = byEntry[candidate.entryIndex, default: []]
                return !windowCandidates.contains { $0.entryIndex != candidate.entryIndex && $0.score >= candidate.score }
                    && !entryCandidates.contains { $0.windowIndex != candidate.windowIndex && $0.score >= candidate.score }
            }
            guard !resolved.isEmpty else { break }
            for candidate in resolved {
                matches[candidate.windowIndex] = entries[candidate.entryIndex]
            }
            let resolvedWindows = Set(resolved.map(\.windowIndex))
            let resolvedEntries = Set(resolved.map(\.entryIndex))
            candidates.removeAll {
                resolvedWindows.contains($0.windowIndex) || resolvedEntries.contains($0.entryIndex)
            }
        }
        return matches
    }

    private func score(entry: CGWindowEntry, for window: AXWindow) -> MatchScore? {
        let titleMatch = Self.titlesMatch(window.title, entry.title)
        let frameComparison = Self.frameComparison(window.frame, entry.bounds)

        if window.frame != nil {
            guard let frameComparison,
                  frameComparison.exact || (titleMatch && frameComparison.overlapScore >= 500_000) else {
                return nil
            }
        } else {
            guard titleMatch else { return nil }
        }

        return MatchScore(
            exactFrame: frameComparison?.exact == true ? 1 : 0,
            titleMatch: titleMatch ? 1 : 0,
            overlapScore: frameComparison?.overlapScore ?? 0,
            distanceScore: frameComparison?.distanceScore ?? Int.min
        )
    }

    static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= frameTolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= frameTolerance &&
            abs(lhs.size.width - rhs.size.width) <= frameTolerance &&
            abs(lhs.size.height - rhs.size.height) <= frameTolerance
    }

    private static func titlesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard
            let lhs,
            let rhs,
            !lhs.isEmpty,
            !rhs.isEmpty
        else {
            return false
        }

        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func frameComparison(_ frame: CGRect?, _ candidateBounds: CGRect) -> FrameComparison? {
        guard let frame else {
            return nil
        }

        if framesMatch(frame, candidateBounds) {
            return FrameComparison(exact: true, overlapScore: Int.max, distanceScore: 0)
        }

        let intersection = frame.intersection(candidateBounds)
        let overlapArea = max(0, intersection.width) * max(0, intersection.height)
        guard overlapArea > 0 else {
            return nil
        }

        let combinedArea = max(frame.width * frame.height, candidateBounds.width * candidateBounds.height)
        let overlapRatio = combinedArea > 0 ? overlapArea / combinedArea : 0
        let distance = hypot(frame.midX - candidateBounds.midX, frame.midY - candidateBounds.midY)

        return FrameComparison(
            exact: false,
            overlapScore: Int(overlapRatio * 1_000_000),
            distanceScore: -Int(distance.rounded())
        )
    }
}

private struct WindowMatchCandidate {
    let windowIndex: Int
    let entryIndex: Int
    let score: MatchScore
}

private struct FrameComparison {
    let exact: Bool
    let overlapScore: Int
    let distanceScore: Int
}

private struct MatchScore: Comparable {
    let exactFrame: Int
    let titleMatch: Int
    let overlapScore: Int
    let distanceScore: Int

    static func < (lhs: MatchScore, rhs: MatchScore) -> Bool {
        if lhs.exactFrame != rhs.exactFrame {
            return lhs.exactFrame < rhs.exactFrame
        }

        if lhs.titleMatch != rhs.titleMatch {
            return lhs.titleMatch < rhs.titleMatch
        }

        if lhs.overlapScore != rhs.overlapScore {
            return lhs.overlapScore < rhs.overlapScore
        }

        return lhs.distanceScore < rhs.distanceScore
    }
}
