import Foundation

/// Backs Overview's "Last 24 Hours — New" stat. A deep walk of
/// Documents/Desktop/Downloads/Pictures/Movies/Music/Public is real, user-noticeable work on a
/// large home folder, so unlike most sections' background auto-refresh, this only ever scans
/// automatically once — the very first time the feature is used, so it isn't stuck showing "not
/// scanned yet" with no explanation. Every scan after that (including every later app launch) is
/// manual only, triggered by the reload button. Results (and when they were captured) are cached
/// to disk so they survive quitting and relaunching instead of resetting to empty every time.
@MainActor
final class RecentActivityViewModel: ObservableObject {
    static let shared = RecentActivityViewModel()

    private enum Keys {
        static let lastScanDate = "recentActivity.lastScanDate"
        static let windowHours = "recentActivity.windowHours"
        static let lastScanWindowHours = "recentActivity.lastScanWindowHours"
    }

    private init() {
        if let cached = ScanCache.load([RecentFile].self, key: "recent_activity"), !cached.isEmpty {
            items = cached
        }
        lastScanDate = UserDefaults.standard.object(forKey: Keys.lastScanDate) as? Date
        let storedWindow = UserDefaults.standard.integer(forKey: Keys.windowHours)
        windowHours = storedWindow == 48 ? 48 : 24
        lastScanWindowHours = UserDefaults.standard.object(forKey: Keys.lastScanWindowHours) as? Int

        if lastScanDate == nil {
            Task { await scan() }
        }
    }

    @Published private(set) var items: [RecentFile] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    /// Either 24 or 48 — a plain `Int`, not an enum, since the only thing that ever reads it is
    /// arithmetic (`windowHours * 60 * 60`) and a label.
    @Published var windowHours: Int {
        didSet { UserDefaults.standard.set(windowHours, forKey: Keys.windowHours) }
    }
    /// The window actually used for whatever's currently in `items` — tracked separately from
    /// `windowHours` because switching the toggle doesn't retroactively reinterpret cached results,
    /// it just changes what the *next* Check Now uses. Lets the UI say "these results are for the
    /// last 24h" even after the toggle's already been flipped to 48h.
    @Published private(set) var lastScanWindowHours: Int?

    func scan() async {
        isScanning = true
        defer { isScanning = false }

        let hours = windowHours
        let cutoff = Date().addingTimeInterval(-Double(hours) * 60 * 60)
        items = await Task.detached(priority: .utility) {
            RecentActivityScanner.scan(since: cutoff)
        }.value
        ScanCache.save(items, key: "recent_activity")

        lastScanDate = Date()
        lastScanWindowHours = hours
        UserDefaults.standard.set(lastScanDate, forKey: Keys.lastScanDate)
        UserDefaults.standard.set(hours, forKey: Keys.lastScanWindowHours)
    }
}
