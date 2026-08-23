import Foundation

/// Tiny per-section disk cache so the last scan results a user saw survive quitting and
/// relaunching the app — without it, every fresh launch starts every section back at its empty
/// "tap Scan" state, even though the same results were on screen five minutes ago. Deliberately
/// read/written as small standalone JSON files (not one big blob) so one section's cache being
/// corrupt or absent never affects another's, and so callers can load synchronously at `init()`
/// without waiting on unrelated data.
enum ScanCache {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("MacMemMan/Cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Synchronous on purpose: these files are small (a scan's worth of items, not raw file
    /// contents) and this is only ever called once from a `.shared` singleton's `init()`, before
    /// anything else can observe the view model — there's no main-thread contention to avoid here,
    /// unlike the real filesystem scans this cache exists to paper over.
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let url = directory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        let url = directory.appendingPathComponent("\(key).json")
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
