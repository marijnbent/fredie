import Observation

@MainActor
@Observable
final class SwitcherSettingsStore {
    var settings = SwitcherSettings()
}
