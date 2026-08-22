import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService` (macOS 13+) for the "Launch at Login" toggle — the modern
/// API lets the main app register itself directly, no separate login-item helper target needed.
enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
