import ApplicationServices

struct AXApplicationWindows: @unchecked Sendable {
    let elements: [AXUIElement]
    let result: AXError
}

struct AXApplicationFocus: @unchecked Sendable {
    let focused: AXUIElement?
    let main: AXUIElement?
    let isComplete: Bool
}

protocol AXWindowReading: Sendable {
    func applicationWindows(pid: pid_t) -> AXApplicationWindows
    func applicationFocus(pid: pid_t) -> AXApplicationFocus
    func readWindow(from element: AXUIElement) -> AXWindowReadResult
}

struct AXWindowInventoryReader: Sendable {
    private let reader: any AXWindowReading

    init(reader: any AXWindowReading = AXWindowReader()) {
        self.reader = reader
    }

    func read(
        pid: pid_t,
        cgEntries: [CGWindowEntry],
        request: WindowRefreshRequest,
        previousWindows: [AXWindow],
        allowUnknownWindows: Bool = false
    ) -> AXAppWindowReadResult {
        if let elements = request.windowElements,
           let windows = updatedWindows(
               pid: pid, elements: elements, cgEntries: cgEntries,
               allowUnknownWindows: allowUnknownWindows,
               updatesFocus: request.updatesFocus, previous: previousWindows
           ) {
            return .updated(windows)
        }
        return readAll(pid: pid, cgEntries: cgEntries, allowUnknownWindows: allowUnknownWindows)
    }

    private func updatedWindows(
        pid: pid_t,
        elements: [AXUIElement],
        cgEntries: [CGWindowEntry],
        allowUnknownWindows: Bool,
        updatesFocus: Bool,
        previous: [AXWindow]
    ) -> [AXWindow]? {
        guard !previous.isEmpty else { return nil }
        var windows = previous
        for element in elements {
            guard let index = windows.firstIndex(where: { CFEqual($0.element, element) }) else {
                return nil
            }
            let window: AXWindow
            switch reader.readWindow(from: element) {
            case .window(let value):
                window = value
            case .unknownWindow(let value) where allowUnknownWindows && hasCGMatch(value, pid: pid, cgEntries: cgEntries):
                window = value
            default:
                return nil
            }
            windows[index] = window.updatingFocus(isFocused: windows[index].isFocused, isMain: windows[index].isMain)
        }
        if updatesFocus {
            let focus = reader.applicationFocus(pid: pid)
            guard focus.isComplete,
                  [focus.focused, focus.main].compactMap({ $0 }).allSatisfy({ element in
                      windows.contains { CFEqual($0.element, element) }
                  }) else {
                return nil
            }
            windows = windows.map { window in
                window.updatingFocus(
                    isFocused: focus.focused.map { CFEqual(window.element, $0) } ?? false,
                    isMain: focus.main.map { CFEqual(window.element, $0) } ?? false
                )
            }
        }
        return windows
    }

    private func readAll(pid: pid_t, cgEntries: [CGWindowEntry], allowUnknownWindows: Bool) -> AXAppWindowReadResult {
        let list = reader.applicationWindows(pid: pid)
        var elements: [AXUIElement] = []
        for element in list.elements { elements.appendIfMissing(element) }
        let focus = reader.applicationFocus(pid: pid)
        if let focused = focus.focused { elements.appendIfMissing(focused) }
        if let main = focus.main { elements.appendIfMissing(main) }

        var windows: [AXWindow] = []
        var unknownWindows: [AXWindow] = []
        var windowReadFailure: AXError?
        for element in elements {
            switch reader.readWindow(from: element) {
            case .window(let window):
                windows.append(window.updatingFocus(focused: focus.focused, main: focus.main))
            case .unknownWindow(let window):
                unknownWindows.append(window.updatingFocus(focused: focus.focused, main: focus.main))
            case .ignored:
                break
            case .failure(let error):
                windowReadFailure = error
            }
        }

        if allowUnknownWindows {
            let matches = WindowOrdering(entries: cgEntries).matches(pid: pid, windows: unknownWindows)
            windows += zip(unknownWindows, matches).compactMap { window, match in
                guard let match, match.bounds.width > 1, match.bounds.height > 1 else { return nil }
                return window
            }
        }

        if !list.result.isCompleteWindowRead {
            return windows.isEmpty ? .failure(list.result) : .partial(windows, list.result)
        }
        if let windowReadFailure {
            return windows.isEmpty ? .failure(windowReadFailure) : .partial(windows, windowReadFailure)
        }
        let cgIndicatesWindow = cgEntries.contains {
            $0.pid == pid && $0.layer == 0 && $0.bounds.width > 1 && $0.bounds.height > 1
        }
        if windows.isEmpty && cgIndicatesWindow {
            return .partial([], .cannotComplete)
        }
        return .success(windows)
    }

    private func hasCGMatch(_ window: AXWindow, pid: pid_t, cgEntries: [CGWindowEntry]) -> Bool {
        guard let match = WindowOrdering(entries: cgEntries).matches(pid: pid, windows: [window]).first ?? nil else {
            return false
        }
        return match.bounds.width > 1 && match.bounds.height > 1
    }
}
