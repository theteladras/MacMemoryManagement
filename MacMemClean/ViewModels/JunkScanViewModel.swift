import Foundation

/// A shared singleton, not a per-view `@StateObject` — see `LargeOldFilesViewModel` for why:
/// this screen is a conditional branch in `RootView`'s switch, and a `@StateObject` gets torn
/// down (losing results and any in-flight scan) every time you navigate away.
@MainActor
final class JunkScanViewModel: ObservableObject {
    static let shared = JunkScanViewModel()
    private init() {
        // Seed from the last scan so this section shows real results the instant the app
        // launches, then quietly kick off one fresh scan in the background — `scan()` itself
        // leaves whatever's already on screen in place while it runs, so this never blanks the
        // list back to a spinner.
        if let cached = ScanCache.load([ScanItem].self, key: "junk_items"), !cached.isEmpty {
            items = cached
            hasScanned = true
            selectedIDs = Set(cached.filter { $0.safety.level.autoSelectByDefault && !$0.category.requiresFullDiskAccess }.map(\.id))
            Task { await scan() }
        }
    }

    @Published var items: [ScanItem] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var statusText = ""
    @Published var hasScanned = false
    /// What's different from the previous scan (including the cached one from last launch) — nil
    /// when this is the first scan ever, or when a rescan found no changes at all.
    @Published var lastChange: ScanChangeSummary?

    var selectedItems: [ScanItem] { items.filter { selectedIDs.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }

    /// Deliberately does not clear `items`/`hasScanned` up front — whatever's already on screen
    /// (from a previous scan, or from the on-disk cache loaded at launch) stays visible the whole
    /// time this runs, so both a background auto-refresh and a manual "Rescan" read as "updating"
    /// rather than "blanking and starting over".
    func scan() async {
        isScanning = true
        statusText = "Scanning known cache, log & junk locations…"
        let previousItems = items
        let isRescan = hasScanned
        defer { isScanning = false; hasScanned = true }

        let found = await Task.detached { JunkScanner.scan() }.value

        items = found.sorted { $0.sizeBytes > $1.sizeBytes }
        // Only pre-select items the safety assessor is confident are disposable. Anything it
        // flagged caution/personal (or that needs Full Disk Access to have been scanned reliably)
        // is left unchecked so the user opts in deliberately.
        selectedIDs = Set(items.filter { $0.safety.level.autoSelectByDefault && !$0.category.requiresFullDiskAccess }.map(\.id))
        ScanCache.save(items, key: "junk_items")

        if isRescan {
            let change = ScanDiff.compute(old: previousItems, new: items)
            lastChange = change.hasChanges ? change : nil
        }
    }

    func toggle(_ item: ScanItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectAll() { selectedIDs = Set(items.map(\.id)) }
    func selectNone() { selectedIDs = [] }

    func removeFromResults(_ items: [ScanItem]) {
        let ids = Set(items.map(\.id))
        self.items.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
    }
}
