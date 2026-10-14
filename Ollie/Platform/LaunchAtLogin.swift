import ServiceManagement
import Foundation

enum LaunchAtLogin {
    static func refreshRegistrationAfterMove() -> String? {
        let path = Bundle.main.bundleURL.path
        let key = "loginItemRegisteredBundlePath"
        guard isEnabled, UserDefaults.standard.string(forKey: key) != path else { return nil }
        do {
            try SMAppService.mainApp.unregister()
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(path, forKey: key)
            return nil
        } catch { return "Could not restore Launch at Login. Turn it on again in General settings." }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("Ollie: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}
