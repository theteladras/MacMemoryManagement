import Foundation

/// A single filesystem entry discovered by a scanner. Scanners only ever
/// produce these — nothing is deleted until the user reviews and confirms
/// a `ReviewManifest` built from a selection of `ScanItem`s.
struct ScanItem: Identifiable, Hashable {
    let id: String
    let path: URL
    let displayName: String
    let category: ScanCategory
    /// Short human-readable explanation of why this item was flagged, e.g. "Not opened in 214 days".
    let reason: String
    let sizeBytes: Int64
    let modifiedAt: Date?
    let isDirectory: Bool
    /// Optional grouping key, e.g. an app's bundle identifier for leftovers, or a duplicate-set id.
    var groupKey: String?

    init(path: URL, category: ScanCategory, reason: String, sizeBytes: Int64, modifiedAt: Date?, isDirectory: Bool, groupKey: String? = nil) {
        self.id = path.path
        self.path = path
        self.displayName = path.lastPathComponent
        self.category = category
        self.reason = reason
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.groupKey = groupKey
    }

    /// Computed on demand rather than stored: it's a pure function of category/path/extension,
    /// and keeping it derived means the heuristics in `SafetyAssessor` can evolve without every
    /// scanner needing to re-run.
    var safety: SafetyAssessment { SafetyAssessor.assess(self) }
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
