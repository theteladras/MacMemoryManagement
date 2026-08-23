import Foundation

/// Persists a running log of everything the app has ever deleted (or tried to), to
/// `~/Library/Application Support/MacMemClean/history.json`. Loaded once at launch, appended to
/// after every Review Sheet confirmation, and written back off the main thread.
@MainActor
final class DeletionHistoryStore: ObservableObject {
    static let shared = DeletionHistoryStore()

    @Published private(set) var entries: [DeletionLogEntry] = []

    private let fileURL: URL
    private var retentionDays: Int { AppSettings.shared.historyRetentionDays }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("MacMemClean", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        entries = Self.load(from: fileURL)
        let before = entries.count
        trimToRetention()
        if entries.count != before { persist() }
    }

    /// Applies the current retention window — called at launch and after every `record()`, same
    /// reasoning as `StorageHistoryStore.trimToRetention()`. This store previously had no
    /// retention at all and grew forever; entries older than the window are now dropped, oldest
    /// first, on each write.
    func trimToRetention() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? .distantPast
        entries.removeAll { $0.date < cutoff }
    }

    /// For Settings to call right when the retention slider moves — otherwise a lowered value
    /// would silently do nothing until the next entry happens to be recorded.
    func applyRetentionNow() {
        let before = entries.count
        trimToRetention()
        if entries.count != before { persist() }
    }

    var totalFreedBytes: Int64 {
        entries.reduce(0) { $0 + ($1.outcome == .deleted ? $1.sizeBytes : 0) }
    }

    func record(operationTitle: String, mode: DeleteMode, result: DeleteResult) {
        var newEntries: [DeletionLogEntry] = []

        for success in result.successes {
            newEntries.append(DeletionLogEntry(
                operationTitle: operationTitle,
                item: success.item,
                mode: mode,
                outcome: .deleted,
                trashedPath: success.trashedURL?.path
            ))
        }
        for failure in result.failed {
            newEntries.append(DeletionLogEntry(
                operationTitle: operationTitle,
                item: failure.item,
                mode: mode,
                outcome: .failed(failure.error)
            ))
        }

        guard !newEntries.isEmpty else { return }
        entries.insert(contentsOf: newEntries.reversed(), at: 0)
        trimToRetention()
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    private func persist() {
        let snapshot = entries
        let url = fileURL
        Task.detached {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [DeletionLogEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DeletionLogEntry].self, from: data)) ?? []
    }
}
