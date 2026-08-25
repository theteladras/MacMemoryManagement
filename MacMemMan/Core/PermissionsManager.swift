import AppKit
import Foundation
import Photos
import UserNotifications

/// A singleton, not a plain nested property of `AppState` — it was one originally, which meant no
/// view ever actually observed it: `AppState`'s own `@Published` properties are what trigger
/// `@EnvironmentObject` updates, and a nested object's `@Published` changes don't propagate
/// through automatically. Every permission row in the app (Full Disk Access, Photos, the sidebar's
/// FDA nudge) looked static as a result — tapping a row could genuinely change its status, proven
/// by debug logging, while the view kept rendering the value from whenever it first appeared.
/// `.shared` + `@ObservedObject` at each call site is the same pattern every other view model in
/// this app already uses, for exactly this reason.
@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var hasFullDiskAccess: Bool = false
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var photosStatus: PHAuthorizationStatus = .notDetermined

    private init() {
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

        photosStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        AppDebugLog.write("PermissionsManager.refresh(): photosStatus=\(photosStatus.rawValue) hasFullDiskAccess=\(hasFullDiskAccess)")
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    func openPhotosSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") else { return }
        let opened = NSWorkspace.shared.open(url)
        AppDebugLog.write("openPhotosSettings(): NSWorkspace.open returned \(opened)")
    }

    /// Covers the per-folder prompts (Desktop, Documents, Downloads, Pictures) macOS asks
    /// individually the first time each is actually touched — there's no API to check or
    /// pre-grant those, so this just opens the pane where they can be reviewed after the fact.
    func openFilesAndFoldersSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Media & Apple Music (the ~/Music folder prompt) — same reasoning as Files and Folders:
    /// no API to check status, this just opens the pane to review it after the fact.
    func openMediaLibrarySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The cases a permission row here can actually flip in-app rather than just deep-linking:
    /// before the user has ever been asked, requesting authorization shows the real system prompt
    /// directly. Once it's been decided either way, only System Settings can change it.
    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func requestPhotos() {
        AppDebugLog.write("PermissionsManager.requestPhotos(): called, currentStatus=\(photosStatus.rawValue)")
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
            AppDebugLog.write("PermissionsManager.requestPhotos(): completion, newStatus=\(newStatus.rawValue)")
            Task { @MainActor in self?.refresh() }
        }
    }
}
