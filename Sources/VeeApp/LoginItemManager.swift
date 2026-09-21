import Foundation
import ServiceManagement
import VeeCore

/// Wraps `SMAppService` (macOS 13+) to launch Vee at login.
@MainActor
public enum LoginItemManager {
    private static let log = VeeLog.make("login-item")

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription, privacy: .public)")
        }
        return isEnabled
    }
}
