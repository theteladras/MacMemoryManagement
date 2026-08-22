import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case explorer = "Storage Explorer"
    case junk = "Caches & Junk"
    case largeOld = "Large & Old Files"
    case duplicates = "Duplicates"
    case compression = "Compress Files"
    case uninstaller = "Applications"
    case history = "History"
    case permissions = "Permissions"
    case settings = "Settings"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .overview: return "chart.pie"
        case .explorer: return "list.bullet.indent"
        case .junk: return "trash.circle"
        case .largeOld: return "doc.badge.clock"
        case .duplicates: return "doc.on.doc"
        case .compression: return "archivebox.fill"
        case .uninstaller: return "square.grid.2x2"
        case .history: return "clock.arrow.circlepath"
        case .permissions: return "hand.raised.fill"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedSection: SidebarSection = .overview
    @Published var deleteMode: DeleteMode = .trash

    /// Set when any view wants to present the mandatory Review Sheet.
    @Published var pendingManifest: ReviewManifest?

    /// Set when a background auto-cleanup check finds something — shown as an approval banner on
    /// Overview rather than immediately interrupting the user with a sheet.
    @Published var pendingAutoCleanupManifest: ReviewManifest?

    let permissions = PermissionsManager()

    func requestReview(_ manifest: ReviewManifest) {
        guard !manifest.items.isEmpty else { return }
        pendingManifest = manifest
    }

    /// Wires the background scheduler's findings into the Overview approval banner, and starts the
    /// periodic check. Called once at app launch.
    func startBackgroundServices() {
        BackgroundCleanupScheduler.shared.onFound = { [weak self] items in
            // Same reasoning as Quick Clean: this is a raw, unfiltered scan result, not a
            // hand-picked selection, so anything not rated "Safe" must start unchecked.
            let riskyIDs = Set(items.filter { $0.safety.level != .safe }.map(\.id))
            self?.pendingAutoCleanupManifest = ReviewManifest(title: "Automatic Cleanup", items: items, preExcludedIDs: riskyIDs)
        }
        BackgroundCleanupScheduler.shared.start()
    }
}
