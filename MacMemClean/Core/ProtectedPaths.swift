import Foundation

/// Hard safety net checked immediately before any delete operation.
/// Nothing under these roots — or matching these exact paths — is ever
/// deletable through the app, regardless of what a scanner produced.
enum ProtectedPaths {
    static let protectedRoots: [String] = [
        "/System", "/bin", "/sbin", "/usr", "/private/var/db",
        "/Library/Apple", "/Applications/Utilities",
        "/Library/Application Support/com.apple.TCC",
    ]

    static var runningAppBundlePath: String {
        Bundle.main.bundlePath
    }

    /// Returns nil if the path is safe to consider for deletion, or a
    /// human-readable reason it must be skipped.
    static func blockReason(for url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        if resolved == "/" || resolved.isEmpty {
            return "Refusing to touch the root volume"
        }
        if resolved == home {
            return "Refusing to touch the entire home folder"
        }
        if resolved == runningAppBundlePath || resolved.hasPrefix(runningAppBundlePath + "/") {
            return "Refusing to delete the running app itself"
        }
        for root in protectedRoots {
            if resolved == root || resolved.hasPrefix(root + "/") {
                return "Path is inside a protected system location"
            }
        }
        return nil
    }
}
