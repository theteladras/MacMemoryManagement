import Foundation

/// A file found by `RecentActivityScanner` — deliberately its own tiny model rather than a
/// `ScanItem`: these are purely informational (Overview's "Last 24 Hours" card), never fed into a
/// `ReviewManifest` or any delete path, so they don't need a category/safety rating at all.
struct RecentFile: Identifiable, Codable {
    let path: String
    let displayName: String
    let sizeBytes: Int64
    let modifiedAt: Date
    /// Which of the scanned root folders this came from (e.g. "Downloads") — shown in the file
    /// list instead of a category, since there isn't one.
    let folder: String

    var id: String { path }
}
