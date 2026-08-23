import Foundation

/// Anything with a stable identity and a size — the common shape `ScanItem`, `AppInfo`, and
/// `CompressionCandidate` already share, which is all a diff needs.
protocol SizedItem: Identifiable {
    var sizeBytes: Int64 { get }
}

extension ScanItem: SizedItem {}
extension AppInfo: SizedItem {}
extension CompressionCandidate: SizedItem {}

/// What changed between one scan and the next — shown as a small banner so re-scanning (manual or
/// the automatic background refresh on relaunch) reads as "here's what's different" instead of
/// silently swapping the list out from under you.
struct ScanChangeSummary {
    let addedCount: Int
    let addedBytes: Int64
    let removedCount: Int
    let removedBytes: Int64

    var hasChanges: Bool { addedCount > 0 || removedCount > 0 }

    var summaryText: String {
        var parts: [String] = []
        if addedCount > 0 { parts.append("+\(addedCount) new (\(addedBytes.formattedBytes))") }
        if removedCount > 0 { parts.append("-\(removedCount) gone (\(removedBytes.formattedBytes))") }
        return parts.isEmpty ? "No changes since your last scan." : "Since last scan: " + parts.joined(separator: " · ")
    }
}

enum ScanDiff {
    /// Compares by identity only (id present before vs. after) — a changed *size* for the same id
    /// isn't currently tracked as its own category, since "this cache folder grew" is far less
    /// actionable than "these are the items that showed up or disappeared".
    static func compute<T: SizedItem>(old: [T], new: [T]) -> ScanChangeSummary {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })

        let addedIDs = Set(newByID.keys).subtracting(oldByID.keys)
        let removedIDs = Set(oldByID.keys).subtracting(newByID.keys)

        let addedBytes = addedIDs.reduce(Int64(0)) { $0 + (newByID[$1]?.sizeBytes ?? 0) }
        let removedBytes = removedIDs.reduce(Int64(0)) { $0 + (oldByID[$1]?.sizeBytes ?? 0) }

        return ScanChangeSummary(
            addedCount: addedIDs.count, addedBytes: addedBytes,
            removedCount: removedIDs.count, removedBytes: removedBytes
        )
    }
}
