import AppKit
import Foundation

/// Small, scalar-ish app-wide preferences that don't fit `AutoCleanupSettings` (scoped to the
/// background scan specifically) — persisted via UserDefaults, same reasoning as that store: a
/// full JSON file would be overkill for values this size.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultDuplicateScanRoots: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
    ]

    private enum Keys {
        static let historyRetentionDays = "app.historyRetentionDays"
        static let menuBarOnlyMode = "app.menuBarOnlyMode"
        static let duplicateScanRoots = "app.duplicateScanRoots"
    }

    private let defaults = UserDefaults.standard

    /// How long `DeletionHistoryStore` and `StorageHistoryStore` keep entries before trimming them
    /// — both read this directly rather than hardcoding their own number.
    @Published var historyRetentionDays: Int {
        didSet { defaults.set(historyRetentionDays, forKey: Keys.historyRetentionDays) }
    }

    /// Hides the Dock icon entirely — MacMemMan becomes a pure menu-bar app, reachable only via
    /// the menu bar dropdown's "Open MacMemMan" row (still there either way) or the wind icon.
    @Published var menuBarOnlyMode: Bool {
        didSet {
            defaults.set(menuBarOnlyMode, forKey: Keys.menuBarOnlyMode)
            applyActivationPolicy()
        }
    }

    /// Where Duplicates looks for matches. Defaults to the same three folders it always has, but
    /// is now editable — someone syncing an external drive or a Projects folder had no way to
    /// include it before.
    @Published var duplicateScanRoots: [URL] {
        didSet { defaults.set(duplicateScanRoots.map(\.path), forKey: Keys.duplicateScanRoots) }
    }

    private init() {
        let storedRetention = defaults.integer(forKey: Keys.historyRetentionDays)
        historyRetentionDays = storedRetention > 0 ? storedRetention : 90
        menuBarOnlyMode = defaults.bool(forKey: Keys.menuBarOnlyMode)
        if let storedPaths = defaults.array(forKey: Keys.duplicateScanRoots) as? [String], !storedPaths.isEmpty {
            duplicateScanRoots = storedPaths.map(URL.init(fileURLWithPath:))
        } else {
            duplicateScanRoots = Self.defaultDuplicateScanRoots
        }
    }

    /// Called once at launch (to apply whatever was persisted from last time) and again every time
    /// `menuBarOnlyMode` changes.
    func applyActivationPolicy() {
        NSApp.setActivationPolicy(menuBarOnlyMode ? .accessory : .regular)
    }

    func addDuplicateScanRoot(_ url: URL) {
        guard !duplicateScanRoots.contains(url) else { return }
        duplicateScanRoots.append(url)
    }

    func removeDuplicateScanRoot(_ url: URL) {
        duplicateScanRoots.removeAll { $0 == url }
    }

    func resetDuplicateScanRoots() {
        duplicateScanRoots = Self.defaultDuplicateScanRoots
    }
}
