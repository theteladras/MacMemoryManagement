import Foundation

/// Persisted (UserDefaults) preferences for the background auto-scan. Small scalar settings, so a
/// full JSON store like `DeletionHistoryStore`/`StorageHistoryStore` would be overkill.
@MainActor
final class AutoCleanupSettings: ObservableObject {
    static let shared = AutoCleanupSettings()

    private enum Keys {
        static let enabled = "autoCleanup.enabled"
        static let frequencyDays = "autoCleanup.frequencyDays"
        static let aggressiveness = "autoCleanup.aggressiveness"
        static let lastRunDate = "autoCleanup.lastRunDate"
        static let autoEmptyTrash = "autoCleanup.autoEmptyTrash"
        static let trashAgeThresholdDays = "autoCleanup.trashAgeThresholdDays"
    }

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }

    /// How often the background check should propose a cleanup, in days.
    @Published var frequencyDays: Int {
        didSet { defaults.set(frequencyDays, forKey: Keys.frequencyDays) }
    }

    @Published var aggressiveness: CleanupAggressiveness {
        didSet { defaults.set(aggressiveness.rawValue, forKey: Keys.aggressiveness) }
    }

    @Published private(set) var lastRunDate: Date?

    /// Unlike every other automatic-cleanup finding, matching Trash items are deleted directly
    /// during the periodic check — no Review Sheet. The reasoning: putting something in the Trash
    /// already *is* the decision to remove it; this just finishes that decision once it's been
    /// sitting there past the threshold, the same way Finder's own "empty Trash automatically"
    /// works. Still routes through `SafeDeleteService` (re-validated against `ProtectedPaths`) and
    /// gets logged to `DeletionHistoryStore`, so nothing about it is invisible after the fact.
    @Published var autoEmptyTrash: Bool {
        didSet { defaults.set(autoEmptyTrash, forKey: Keys.autoEmptyTrash) }
    }
    @Published var trashAgeThresholdDays: Int {
        didSet { defaults.set(trashAgeThresholdDays, forKey: Keys.trashAgeThresholdDays) }
    }

    private init() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        let storedFrequency = defaults.integer(forKey: Keys.frequencyDays)
        frequencyDays = storedFrequency > 0 ? storedFrequency : 3
        aggressiveness = CleanupAggressiveness(rawValue: defaults.string(forKey: Keys.aggressiveness) ?? "") ?? .balanced
        lastRunDate = defaults.object(forKey: Keys.lastRunDate) as? Date
        autoEmptyTrash = defaults.bool(forKey: Keys.autoEmptyTrash)
        let storedTrashAge = defaults.integer(forKey: Keys.trashAgeThresholdDays)
        trashAgeThresholdDays = storedTrashAge > 0 ? storedTrashAge : 30
    }

    func recordRun(date: Date = Date()) {
        lastRunDate = date
        defaults.set(date, forKey: Keys.lastRunDate)
    }
}
