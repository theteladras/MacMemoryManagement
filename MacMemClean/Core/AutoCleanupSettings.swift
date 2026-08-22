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

    private init() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        let storedFrequency = defaults.integer(forKey: Keys.frequencyDays)
        frequencyDays = storedFrequency > 0 ? storedFrequency : 3
        aggressiveness = CleanupAggressiveness(rawValue: defaults.string(forKey: Keys.aggressiveness) ?? "") ?? .balanced
        lastRunDate = defaults.object(forKey: Keys.lastRunDate) as? Date
    }

    func recordRun(date: Date = Date()) {
        lastRunDate = date
        defaults.set(date, forKey: Keys.lastRunDate)
    }
}
