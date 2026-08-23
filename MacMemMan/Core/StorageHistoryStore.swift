import Foundation

/// One category's size at the moment a snapshot was taken — kept name-only (not a full
/// `DiskCategoryUsage`, whose `tint` is a `Color` and not `Codable`) since the trend chart re-maps
/// the name back to a color itself.
struct CategorySnapshot: Codable {
    let name: String
    let bytes: Int64
}

struct StorageSnapshot: Identifiable, Codable {
    let id: UUID
    let date: Date
    let usedBytes: Int64
    let freeBytes: Int64
    let totalBytes: Int64
    let breakdown: [CategorySnapshot]

    init(id: UUID, date: Date, usedBytes: Int64, freeBytes: Int64, totalBytes: Int64, breakdown: [CategorySnapshot]) {
        self.id = id
        self.date = date
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        self.breakdown = breakdown
    }

    /// Custom decode so snapshots recorded before `breakdown` existed still load — they just get an
    /// empty breakdown (the total-usage line still works, only the per-location lines are missing
    /// for that older point) instead of silently discarding the whole history file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        usedBytes = try container.decode(Int64.self, forKey: .usedBytes)
        freeBytes = try container.decode(Int64.self, forKey: .freeBytes)
        totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
        breakdown = try container.decodeIfPresent([CategorySnapshot].self, forKey: .breakdown) ?? []
    }
}

/// Persists periodic snapshots of disk usage — both the total and the per-location breakdown — so
/// Overview can chart a trend over time, not just the current moment. Stored at
/// `~/Library/Application Support/MacMemMan/storage_history.json`.
@MainActor
final class StorageHistoryStore: ObservableObject {
    static let shared = StorageHistoryStore()

    @Published private(set) var snapshots: [StorageSnapshot] = []

    private let fileURL: URL
    private let minIntervalBetweenSnapshots: TimeInterval = 60 * 60 // don't spam on repeated refreshes
    private var retentionDays: Int { AppSettings.shared.historyRetentionDays }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("MacMemMan", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("storage_history.json")
        snapshots = Self.load(from: fileURL)
        let before = snapshots.count
        trimToRetention()
        if snapshots.count != before { persist() }
    }

    /// Applies the current retention window — called at launch and from `record()`, so lowering
    /// the setting in Settings takes effect right away rather than waiting for the next snapshot.
    /// Just mutates `snapshots`; callers decide whether/when to persist.
    func trimToRetention() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? .distantPast
        snapshots.removeAll { $0.date < cutoff }
    }

    /// For Settings to call right when the retention slider moves — otherwise a lowered value
    /// would silently do nothing until the next snapshot happens to be recorded.
    func applyRetentionNow() {
        let before = snapshots.count
        trimToRetention()
        if snapshots.count != before { persist() }
    }

    func record(summary: DiskUsageSummary) {
        guard summary.totalBytes > 0 else { return }
        if let last = snapshots.last, Date().timeIntervalSince(last.date) < minIntervalBetweenSnapshots {
            return
        }
        // Include "Other" as its own line, same as the capacity bar on Overview — without it the
        // trend chart's "Total Used" line sits far above every category line with no visual
        // explanation, since the tracked categories rarely account for most of a disk.
        var breakdown = summary.breakdown.map { CategorySnapshot(name: $0.name, bytes: $0.bytes) }
        if summary.otherBytes > 0 {
            breakdown.append(CategorySnapshot(name: "Other", bytes: summary.otherBytes))
        }
        let snapshot = StorageSnapshot(
            id: UUID(),
            date: Date(),
            usedBytes: summary.usedBytes,
            freeBytes: summary.freeBytes,
            totalBytes: summary.totalBytes,
            breakdown: breakdown
        )
        snapshots.append(snapshot)
        trimToRetention()
        persist()
    }

    private func persist() {
        let snapshot = snapshots
        let url = fileURL
        Task.detached {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [StorageSnapshot] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([StorageSnapshot].self, from: data)) ?? []
    }
}
