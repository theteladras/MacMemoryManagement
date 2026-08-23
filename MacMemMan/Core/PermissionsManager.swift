import AppKit
import Foundation
import UserNotifications

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var hasFullDiskAccess: Bool = false
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    init() {
        refresh()
    }

    /// There is no public API to query TCC's Full Disk Access state directly, so we probe by
    /// attempting to read a location that is only reachable with FDA granted.
    func refresh() {
        let probePaths = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            NSHomeDirectory() + "/Library/Safari/CloudTabs.db",
        ]
        hasFullDiskAccess = probePaths.contains { FileManager.default.isReadableFile(atPath: $0) }

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in self?.notificationStatus = settings.authorizationStatus }
        }
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The one case a permission row here can actually flip in-app rather than just deep-linking:
    /// before the user has ever been asked, requesting authorization shows the real system prompt
    /// directly. Once it's been decided either way, only System Settings can change it.
    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}
