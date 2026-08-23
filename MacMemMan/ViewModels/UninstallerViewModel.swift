import Foundation

/// A shared singleton, not a per-view `@StateObject` — see `LargeOldFilesViewModel` for why.
@MainActor
final class UninstallerViewModel: ObservableObject {
    static let shared = UninstallerViewModel()
    private init() {
        // Seed from the last load so this section shows real apps (icons included) the instant
        // the app launches, then quietly kick off a fresh load in the background — `loadApps()`
        // itself leaves whatever's already on screen in place while it runs.
        if let cached = ScanCache.load([AppInfo].self, key: "uninstaller_apps"), !cached.isEmpty {
            apps = cached
            hasLoadedOnce = true
            Task { await loadApps() }
        }
    }

    @Published var apps: [AppInfo] = []
    @Published var isLoading = false
    @Published var selectedApp: AppInfo?
    @Published var plan: UninstallPlan?
    @Published var isLoadingPlan = false
    @Published var selectedLeftoverIDs: Set<String> = []
    /// Which apps got installed or removed since the last load — nil on the very first load, or
    /// when a refresh found the same set of apps as before.
    @Published var lastChange: ScanChangeSummary?

    /// Leftover kinds that are effectively equivalent to a regular app cache — safe to clear
    /// whether or not you keep the app installed, so these are the only ones pre-checked.
    private static let cacheLikeReasons: Set<String> = ["Cache", "Logs"]
    private var hasLoadedOnce = false

    func loadApps() async {
        isLoading = true
        let previousApps = apps
        let isReload = hasLoadedOnce
        defer { isLoading = false; hasLoadedOnce = true }

        apps = await Task.detached { AppUninstaller.installedApps() }.value
        ScanCache.save(apps, key: "uninstaller_apps")

        if isReload {
            let change = ScanDiff.compute(old: previousApps, new: apps)
            lastChange = change.hasChanges ? change : nil
        }
    }

    func selectApp(_ app: AppInfo) async {
        selectedApp = app
        plan = nil
        selectedLeftoverIDs = []
        isLoadingPlan = true
        defer { isLoadingPlan = false }
        let loadedPlan = await Task.detached { AppUninstaller.leftoverPlan(for: app) }.value
        plan = loadedPlan
        selectedLeftoverIDs = Set(
            loadedPlan.items
                .filter { $0.path != app.bundlePath && Self.cacheLikeReasons.contains($0.reason) }
                .map(\.id)
        )
    }

    func toggleLeftover(_ item: ScanItem) {
        if selectedLeftoverIDs.contains(item.id) {
            selectedLeftoverIDs.remove(item.id)
        } else {
            selectedLeftoverIDs.insert(item.id)
        }
    }

    var selectedLeftoverItems: [ScanItem] {
        (plan?.items ?? []).filter { selectedLeftoverIDs.contains($0.id) }
    }

    var selectedLeftoverBytes: Int64 { selectedLeftoverItems.reduce(0) { $0 + $1.sizeBytes } }

    /// Called after "Clean Selected…" (leftovers only, app stays installed) successfully deletes
    /// some items — prunes them from the current plan so they don't linger in the list looking
    /// undeleted. `UninstallPlan.items` is immutable by design, so this rebuilds the plan rather
    /// than mutating it in place.
    func removeLeftoverItems(withIDs ids: Set<String>) {
        guard let plan else { return }
        let remaining = plan.items.filter { !ids.contains($0.id) }
        self.plan = UninstallPlan(app: plan.app, items: remaining)
        selectedLeftoverIDs.subtract(ids)
    }

    func removeApp(withID id: String) {
        apps.removeAll { $0.id == id }
        if selectedApp?.id == id {
            selectedApp = nil
            plan = nil
            selectedLeftoverIDs = []
        }
    }
}
