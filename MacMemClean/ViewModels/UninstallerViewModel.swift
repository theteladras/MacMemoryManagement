import Foundation

@MainActor
final class UninstallerViewModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var isLoading = false
    @Published var selectedApp: AppInfo?
    @Published var plan: UninstallPlan?
    @Published var isLoadingPlan = false
    @Published var selectedLeftoverIDs: Set<String> = []

    /// Leftover kinds that are effectively equivalent to a regular app cache — safe to clear
    /// whether or not you keep the app installed, so these are the only ones pre-checked.
    private static let cacheLikeReasons: Set<String> = ["Cache", "Logs"]

    func loadApps() async {
        isLoading = true
        defer { isLoading = false }
        apps = await Task.detached { AppUninstaller.installedApps() }.value
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

    func removeApp(withID id: String) {
        apps.removeAll { $0.id == id }
        if selectedApp?.id == id {
            selectedApp = nil
            plan = nil
            selectedLeftoverIDs = []
        }
    }
}
