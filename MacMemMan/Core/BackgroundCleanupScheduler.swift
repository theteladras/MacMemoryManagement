import Foundation
import UserNotifications

/// Periodically (while the app is running) checks whether it's time to propose a cleanup, based on
/// `AutoCleanupSettings`. It only ever *finds* things — exactly like every manual scan — and hands
/// the results back via `onFound` so the UI can show an approval banner and/or a system
/// notification. Nothing is ever deleted without the user confirming in the Review screen.
///
/// Note: this runs on a timer while MacMemMan is open, not as a true background daemon — the app
/// still needs to be running for a check to fire. A launch-at-login helper would be a separate,
/// bigger addition if that's ever needed.
@MainActor
final class BackgroundCleanupScheduler: ObservableObject {
    static let shared = BackgroundCleanupScheduler()

    /// Called on the main actor with whatever a due scan found. Wired up by `AppState` so the
    /// Overview screen can show an approval banner.
    var onFound: (([ScanItem]) -> Void)?

    private let settings = AutoCleanupSettings.shared
    private var timer: Timer?
    private var isRunning = false

    private init() {}

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in
            Task { @MainActor in await BackgroundCleanupScheduler.shared.checkAndRunIfDue() }
        }
        Task { await checkAndRunIfDue() }
    }

    /// `force: true` bypasses the enabled toggle and the frequency interval — used by the
    /// "Run Now" button in Settings.
    func checkAndRunIfDue(force: Bool = false) async {
        guard !isRunning else { return }
        guard force || settings.isEnabled else { return }

        if !force, let last = settings.lastRunDate {
            let interval = TimeInterval(settings.frequencyDays * 24 * 60 * 60)
            guard Date().timeIntervalSince(last) >= interval else { return }
        }

        isRunning = true
        defer { isRunning = false }

        if settings.autoEmptyTrash {
            await emptyOldTrashItems()
        }

        let aggressiveness = settings.aggressiveness
        let items = await Task.detached { Self.performScan(aggressiveness: aggressiveness) }.value

        settings.recordRun()

        guard !items.isEmpty else { return }
        onFound?(items)
        postNotification(for: items)
    }

    /// The one deletion path in the whole app that skips the Review Sheet — see the comment on
    /// `AutoCleanupSettings.autoEmptyTrash` for why that's an intentional exception, not a
    /// shortcut. Still funnels through `SafeDeleteService` (re-validated against `ProtectedPaths`
    /// immediately before removal) and gets logged to `DeletionHistoryStore`.
    private func emptyOldTrashItems() async {
        let days = settings.trashAgeThresholdDays
        let items = await Task.detached { Self.oldTrashItems(olderThanDays: days) }.value
        guard !items.isEmpty else { return }

        let outcome = await SafeDeleteService.delete(items, mode: .permanent)
        DeletionHistoryStore.shared.record(operationTitle: "Automatic Trash Cleanup", mode: .permanent, result: outcome)
    }

    /// Ages Trash contents by when they were *moved into* `.Trash` (`addedToDirectoryDate`), not
    /// by their own content modification date — a photo trashed yesterday shouldn't count as
    /// "old" just because it was taken years ago. Falls back to modification date only if that
    /// resource value is unavailable.
    private nonisolated static func oldTrashItems(olderThanDays days: Int) -> [ScanItem] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let listing = FileSystemScanner.immediateChildren(of: trashURL, includeHidden: true)

        return listing.entries.compactMap { entry -> ScanItem? in
            let addedDate = (try? entry.url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? entry.modifiedAt
            guard let addedDate, addedDate < cutoff else { return nil }
            let dateLabel = DateFormatter.localizedString(from: addedDate, dateStyle: .medium, timeStyle: .none)
            return ScanItem(
                path: entry.url,
                category: .trash,
                reason: "In Trash since \(dateLabel)",
                sizeBytes: entry.sizeBytes,
                modifiedAt: entry.modifiedAt,
                isDirectory: entry.isDirectory
            )
        }
    }

    private nonisolated static func performScan(aggressiveness: CleanupAggressiveness) -> [ScanItem] {
        var items = JunkScanner.scan().filter { $0.safety.level == .safe }

        guard aggressiveness != .light else { return items }

        var largeOldOptions = LargeOldFilesScanner.Options()
        largeOldOptions.root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        if aggressiveness == .aggressive {
            largeOldOptions.minSizeBytes = 50 * 1024 * 1024
            largeOldOptions.minAgeDays = 90
        }
        let (large, old) = LargeOldFilesScanner.scan(options: largeOldOptions)
        items += large + old

        if aggressiveness == .aggressive {
            let duplicateGroups = DuplicateFinder.scan(options: .init())
            for group in duplicateGroups {
                items += group.items.dropFirst().filter { $0.safety.level != .personal }
            }
        }

        return items
    }

    private func postNotification(for items: [ScanItem]) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let total = items.reduce(0) { $0 + $1.sizeBytes }
            let content = UNMutableNotificationContent()
            content.title = "MacMemMan found space to free up"
            content.body = "\(items.count) item(s) — \(total.formattedBytes) reclaimable. Open the app to review."
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }

    func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}
