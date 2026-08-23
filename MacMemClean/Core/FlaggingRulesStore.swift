import Foundation

/// Persists user-defined flagging rules and answers `SafetyAssessor`'s "does anything override
/// this item" question. Deliberately *not* `@MainActor` — `SafetyAssessor.assess(_:)` runs from
/// wherever a `ScanItem.safety` happens to be read, which in practice is always the main actor
/// today, but making that a hard requirement here would be one refactor away from a crash. A lock
/// over a plain snapshot array keeps reads safe from any thread; the `@Published` copy exists
/// purely so the Settings UI can observe changes.
final class FlaggingRulesStore: ObservableObject {
    static let shared = FlaggingRulesStore()

    // Mutated only from SwiftUI UI code (always the main thread in practice); `matchingTreatment`
    // below — the one method meant to be called from anywhere, including background scan threads
    // — never touches this directly, only the lock-protected `snapshot`.
    @Published private(set) var rules: [FlaggingRule] = []

    private let lock = NSLock()
    private var snapshot: [FlaggingRule] = []
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("MacMemClean", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("flagging_rules.json")

        let loaded = Self.load(from: fileURL)
        rules = loaded
        snapshot = loaded
    }

    func add(_ rule: FlaggingRule) {
        rules.append(rule)
        persist()
    }

    func update(_ rule: FlaggingRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        persist()
    }

    func remove(_ id: FlaggingRule.ID) {
        rules.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ id: FlaggingRule.ID, _ enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        persist()
    }

    private func persist() {
        lock.lock()
        snapshot = rules
        lock.unlock()

        let toSave = rules
        let url = fileURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(toSave) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The one method `SafetyAssessor` calls — safe from any thread. Returns the treatment of the
    /// first enabled rule that matches, in the order the user created them, or `nil` if nothing
    /// matches (the normal case, and the fast path: usually zero rules exist at all).
    func matchingTreatment(for item: ScanItem) -> FlaggingRule.Treatment? {
        lock.lock()
        let current = snapshot
        lock.unlock()

        guard !current.isEmpty else { return nil }

        let name = item.displayName
        let ext = item.path.pathExtension
        let fullPath = item.path.path

        for rule in current where rule.isEnabled {
            let trimmedPattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPattern.isEmpty else { continue }

            switch rule.matchType {
            case .namePattern:
                if Self.matchesGlob(name, pattern: trimmedPattern) { return rule.treatment }
            case .fileExtension:
                let normalized = trimmedPattern.hasPrefix(".") ? String(trimmedPattern.dropFirst()) : trimmedPattern
                if ext.caseInsensitiveCompare(normalized) == .orderedSame { return rule.treatment }
            case .path:
                let expanded = (trimmedPattern as NSString).expandingTildeInPath
                if fullPath == expanded || fullPath.hasPrefix(expanded.hasSuffix("/") ? expanded : expanded + "/") {
                    return rule.treatment
                }
            }
        }
        return nil
    }

    /// `*`/`?` glob matching via Foundation's own `LIKE` predicate operator — battle-tested,
    /// case-insensitive, no custom regex needed for the common "contains"/"starts with" patterns
    /// this is for (`*invoice*`, `backup-*.zip`).
    private static func matchesGlob(_ value: String, pattern: String) -> Bool {
        let effectivePattern = pattern.contains("*") || pattern.contains("?") ? pattern : "*\(pattern)*"
        return NSPredicate(format: "SELF LIKE[c] %@", effectivePattern).evaluate(with: value)
    }

    private static func load(from url: URL) -> [FlaggingRule] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([FlaggingRule].self, from: data)) ?? []
    }
}
