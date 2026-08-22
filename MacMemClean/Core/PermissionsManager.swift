import AppKit
import Foundation

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var hasFullDiskAccess: Bool = false

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
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
