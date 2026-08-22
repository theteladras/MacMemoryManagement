import Foundation

/// The single object that flows into the mandatory Review Sheet before any
/// deletion happens. Built from whatever the user has selected/checked in
/// any scan view.
struct ReviewManifest {
    var title: String
    var items: [ScanItem]
    /// Item IDs that should start **unchecked** in the Review Sheet. Views that already only pass
    /// along a hand-picked selection (Junk/Large&Old/Duplicates/Uninstaller — the user already
    /// checked exactly what they want) leave this empty, since everything they send is meant to
    /// stay checked. Flows that dump raw, unfiltered scan results straight into Review — Quick
    /// Clean and the automatic background scan — use this to keep caution/personal items visible
    /// but off by default, the same "only Safe is pre-selected" rule every other scanner follows.
    var preExcludedIDs: Set<String> = []

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    var count: Int { items.count }

    var groupedByCategory: [(category: ScanCategory, items: [ScanItem])] {
        let grouped = Dictionary(grouping: items, by: \.category)
        return ScanCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category, items.sorted { $0.sizeBytes > $1.sizeBytes })
        }
    }
}

enum DeleteMode: String, Codable {
    case trash
    case permanent
}

struct DeleteResult {
    struct Success {
        let item: ScanItem
        /// Where the item landed in the Trash, when known — lets History offer "Reveal in Finder".
        let trashedURL: URL?
    }

    var freedBytes: Int64 = 0
    var successes: [Success] = []
    var failed: [(item: ScanItem, error: String)] = []

    var succeeded: Int { successes.count }
}
