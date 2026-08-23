import Foundation

/// A shared singleton, not a per-view `@StateObject` — this screen is a conditional branch in
/// `RootView`'s switch, and SwiftUI tears down a `@StateObject` in an inactive branch. Without a
/// persistent instance, navigating away and back would lose the scan results and any selection,
/// forcing a full rescan every time.
@MainActor
final class LargeOldFilesViewModel: ObservableObject {
    static let shared = LargeOldFilesViewModel()
    private init() {
        // Seed from the last scan so this section shows real results the instant the app
        // launches, then quietly kick off one fresh scan in the background — `scan()` itself
        // leaves whatever's already on screen in place while it runs.
        let cachedLarge = ScanCache.load([ScanItem].self, key: "largeold_large") ?? []
        let cachedOld = ScanCache.load([ScanItem].self, key: "largeold_old") ?? []
        if !cachedLarge.isEmpty || !cachedOld.isEmpty {
            largeItems = cachedLarge
            oldItems = cachedOld
            hasScanned = true
            Task { await scan() }
        }
    }

    @Published var largeItems: [ScanItem] = []
    @Published var oldItems: [ScanItem] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var minSizeMB: Double = 100
    @Published var minAgeDays: Int = 180
    @Published var scanRoot: URL = FileManager.default.homeDirectoryForCurrentUser
    /// What's different from the previous scan — nil when this is the first scan ever, or when a
    /// rescan found no changes at all.
    @Published var lastChange: ScanChangeSummary?

    /// View-only filters — narrow what's displayed without touching `selectedIDs`, so toggling a
    /// filter never silently drops a selection the user already made on a now-hidden item.
    @Published var safetyFilter: SafetyLevel?
    @Published var typeFilter: FileTypeCategory?

    var allItems: [ScanItem] { largeItems + oldItems }
    var selectedItems: [ScanItem] { allItems.filter { selectedIDs.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }

    var filteredLargeItems: [ScanItem] { applyFilters(largeItems) }
    var filteredOldItems: [ScanItem] { applyFilters(oldItems) }
    var hasActiveFilters: Bool { safetyFilter != nil || typeFilter != nil }

    /// Only offer type choices that actually occur in the current results, so the menu isn't full
    /// of categories that would just produce an empty list.
    var availableTypeFilters: [FileTypeCategory] {
        let present = Set(allItems.map { FileTypeAnalyzer.category(forExtension: $0.path.pathExtension) })
        return FileTypeCategory.allCases.filter { present.contains($0) }
    }

    private func applyFilters(_ items: [ScanItem]) -> [ScanItem] {
        items.filter { item in
            (safetyFilter == nil || item.safety.level == safetyFilter)
                && (typeFilter == nil || FileTypeAnalyzer.category(forExtension: item.path.pathExtension) == typeFilter)
        }
    }

    /// Deliberately does not clear existing results up front — see `JunkScanViewModel.scan()` for
    /// why: whatever's already on screen (cached or from a previous scan) stays visible while this
    /// runs, so a background refresh reads as "updating" rather than "starting over".
    func scan() async {
        isScanning = true
        let previousItems = allItems
        let isRescan = hasScanned
        defer { isScanning = false; hasScanned = true }

        let root = scanRoot
        let minSize = Int64(minSizeMB * 1024 * 1024)
        let minAge = minAgeDays

        let result = await Task.detached {
            var options = LargeOldFilesScanner.Options()
            options.root = root
            options.minSizeBytes = minSize
            options.minAgeDays = minAge
            return LargeOldFilesScanner.scan(options: options)
        }.value
        largeItems = result.large
        oldItems = result.old
        selectedIDs = []
        ScanCache.save(largeItems, key: "largeold_large")
        ScanCache.save(oldItems, key: "largeold_old")

        if isRescan {
            let change = ScanDiff.compute(old: previousItems, new: allItems)
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

    func removeFromResults(_ items: [ScanItem]) {
        let ids = Set(items.map(\.id))
        largeItems.removeAll { ids.contains($0.id) }
        oldItems.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
    }
}
