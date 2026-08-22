import AppKit
import Foundation

struct AppInfo: Identifiable, Hashable {
    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: String // bundle path, stable per app
    let bundlePath: URL
    let bundleIdentifier: String?
    let name: String
    let version: String?
    let sizeBytes: Int64
    let icon: NSImage?
    let lastUsedDate: Date?

    var lastUsedLabel: String {
        guard let lastUsedDate else { return "Last used: unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last used " + formatter.localizedString(for: lastUsedDate, relativeTo: Date())
    }

    /// Hasn't been opened in 6+ months — a signal (not a verdict) that this might be worth
    /// reconsidering, surfaced the same way stale files are elsewhere in the app.
    var isStale: Bool {
        guard let lastUsedDate else { return false }
        return Date().timeIntervalSince(lastUsedDate) > 60 * 60 * 24 * 180
    }
}

/// Everything found for a single app when the user asks to uninstall it:
/// the app bundle itself plus any leftover support files elsewhere on disk.
struct UninstallPlan {
    let app: AppInfo
    let items: [ScanItem]
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
}
