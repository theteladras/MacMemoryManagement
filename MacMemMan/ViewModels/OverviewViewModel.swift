import Foundation

/// A shared singleton, not a per-view `@StateObject` — Overview is a conditional branch in
/// `RootView`'s switch, and SwiftUI fully tears down and recreates a conditional branch's views
/// (and any `@StateObject`s inside them) every time you navigate away and back. Without a
/// persistent instance here, "stale data while refreshing" is impossible to show because there's
/// no previous data left by the time you return — it looks like a fresh, empty load every time.
@MainActor
final class OverviewViewModel: ObservableObject {
    static let shared = OverviewViewModel()
    private init() {
        // Seed from the last run's results so Overview shows real numbers the instant the app
        // launches instead of a blank/zeroed hero card — `loadSummary()` still runs fresh right
        // after (see `OverviewView`'s `.task`), and because `lastUpdated` stays nil here, that
        // call is never throttled just because a cache happened to load.
        if let cached = ScanCache.load(CachedDiskUsageSummary.self, key: "overview_summary") {
            summary = DiskUsageSummary(cached: cached)
        }
        if let cachedTypes = ScanCache.load([FileTypeAnalyzer.TypeUsage].self, key: "overview_types") {
            typeBreakdown = cachedTypes
            hasAnalyzedTypes = true
        }
    }

    @Published var summary = DiskUsageSummary()
    @Published var isLoadingSummary = false
    @Published var lastUpdated: Date?
    @Published var isSmartScanning = false
    @Published var smartScanStatus = ""
    @Published var smartScanItems: [ScanItem] = []

    @Published var typeBreakdown: [FileTypeAnalyzer.TypeUsage] = []
    @Published var isAnalyzingTypes = false
    @Published var hasAnalyzedTypes = false

    /// One-level drill-down into a tapped capacity-bar segment — e.g. tapping "Documents & Desktop"
    /// shows Documents vs Desktop. `nil` category means no drill-down panel is showing.
    @Published var drillDownCategory: String?
    @Published var drillDownSegments: [DiskCategoryUsage] = []
    @Published var isLoadingDrillDown = false

    /// Below this, revisiting Overview reuses whatever's already on screen instead of kicking off
    /// another full rescan — `force: true` (the manual refresh button) always bypasses it.
    private let minRefreshInterval: TimeInterval = 60

    /// Walks Applications/Documents/Desktop/Downloads/Pictures/Movies/Music/Library recursively to
    /// size them — genuinely slow (Library especially), so it must never run on the main thread.
    /// The previous `summary` is left in place while this runs, so the UI can show it labeled
    /// "stale" instead of blanking out during the refresh.
    func loadSummary(force: Bool = false) async {
        guard !isLoadingSummary else { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < minRefreshInterval {
            return
        }
        isLoadingSummary = true
        defer { isLoadingSummary = false }
        summary = await Task.detached { DiskUsageAnalyzer.summary() }.value
        lastUpdated = Date()
        ScanCache.save(summary.cached, key: "overview_summary")
        StorageHistoryStore.shared.record(summary: summary)
    }

    /// Toggles the one-level drill-down panel for a tapped capacity-bar/legend segment. Tapping
    /// the same category again collapses it; categories with no further breakdown (Other, Free)
    /// simply have nothing to show.
    func toggleDrillDown(_ categoryName: String) async {
        if drillDownCategory == categoryName {
            drillDownCategory = nil
            drillDownSegments = []
            return
        }
        drillDownCategory = categoryName
        isLoadingDrillDown = true
        defer { isLoadingDrillDown = false }
        let otherBytes = summary.otherBytes
        drillDownSegments = await Task.detached { DiskUsageAnalyzer.drillDown(for: categoryName, otherTotalBytes: otherBytes) ?? [] }.value
    }

    /// Scans Documents/Desktop/Downloads/Pictures/Movies/Music/Public and buckets every file by
    /// what it actually is, so media hiding in Downloads or Desktop still shows up as media.
    func analyzeByType() async {
        isAnalyzingTypes = true
        hasAnalyzedTypes = false
        defer { isAnalyzingTypes = false; hasAnalyzedTypes = true }

        typeBreakdown = await Task.detached { FileTypeAnalyzer.analyze() }.value
        ScanCache.save(typeBreakdown, key: "overview_types")
    }

    /// Runs the junk scan + a quick large-file pass together, producing one combined result set
    /// for the flagship "Smart Scan" flow.
    func runSmartScan() async {
        isSmartScanning = true
        smartScanItems = []
        defer { isSmartScanning = false }

        smartScanStatus = "Scanning caches, logs & junk…"
        let junk = await Task.detached { JunkScanner.scan() }.value

        smartScanStatus = "Looking for large files…"
        let downloadsRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let (large, _) = await Task.detached {
            var options = LargeOldFilesScanner.Options()
            options.root = downloadsRoot
            return LargeOldFilesScanner.scan(options: options)
        }.value

        smartScanStatus = "Done"
        smartScanItems = junk + large
    }

    func removeFromSmartScanResults(_ items: [ScanItem]) {
        let ids = Set(items.map(\.id))
        smartScanItems.removeAll { ids.contains($0.id) }
    }
}
