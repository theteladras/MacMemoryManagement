import Foundation

enum LargeOldFilesScanner {
    struct Options {
        var root: URL = FileManager.default.homeDirectoryForCurrentUser
        var minSizeBytes: Int64 = 100 * 1024 * 1024 // 100 MB
        var minAgeDays: Int = 180
        /// Skip common system/library noise so results stay relevant to the user's own files.
        var excludedPathComponents: Set<String> = ["Library", "node_modules", ".git", ".Trash"]
    }

    static func scan(options: Options, onProgress: @escaping (Int) -> Void = { _ in }) -> (large: [ScanItem], old: [ScanItem]) {
        var large: [ScanItem] = []
        var old: [ScanItem] = []
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -options.minAgeDays, to: Date())
        var scanned = 0

        FileSystemScanner.walkFiles(root: options.root, filter: { entry in
            let components = Set(entry.url.pathComponents)
            if !components.isDisjoint(with: options.excludedPathComponents) { return false }
            return true
        }, onEntry: { entry in
            scanned += 1
            if scanned % 500 == 0 { onProgress(scanned) }

            if entry.sizeBytes >= options.minSizeBytes {
                large.append(ScanItem(
                    path: entry.url,
                    category: .largeFiles,
                    reason: "\(entry.sizeBytes.formattedBytes) file",
                    sizeBytes: entry.sizeBytes,
                    modifiedAt: entry.modifiedAt,
                    isDirectory: false
                ))
            }

            if let cutoffDate, let modified = entry.modifiedAt, modified < cutoffDate, entry.sizeBytes > 1024 * 1024 {
                let days = Calendar.current.dateComponents([.day], from: modified, to: Date()).day ?? options.minAgeDays
                old.append(ScanItem(
                    path: entry.url,
                    category: .oldFiles,
                    reason: "Not modified in \(days) days",
                    sizeBytes: entry.sizeBytes,
                    modifiedAt: entry.modifiedAt,
                    isDirectory: false
                ))
            }
        })

        return (large.sorted { $0.sizeBytes > $1.sizeBytes }, old.sorted { $0.sizeBytes > $1.sizeBytes })
    }
}
