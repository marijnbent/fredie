import Foundation

enum WindowActivation {
    @MainActor
    static func perform(
        target: SwitcherItem,
        request: @MainActor (SwitcherItem) async -> Void,
        isFocused: @MainActor (SwitcherItem) async -> Bool,
        refreshTarget: @MainActor (SwitcherItem) async -> SwitcherItem?,
        canContinue: @MainActor () -> Bool,
        pause: @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(50)) }
    ) async -> SwitcherItem? {
        var target = target
        for attempt in 0..<2 {
            guard !Task.isCancelled, canContinue() else { return nil }
            await request(target)
            for check in 0..<4 {
                guard !Task.isCancelled, canContinue() else { return nil }
                let focused = await isFocused(target)
                guard !Task.isCancelled, canContinue() else { return nil }
                if focused { return target }
                if check < 3 {
                    do { try await pause() }
                    catch { return nil }
                }
            }
            if attempt == 0 {
                let refreshed = await refreshTarget(target)
                guard !Task.isCancelled, canContinue(), let refreshed else { return nil }
                target = refreshed
            }
        }
        return nil
    }
}
