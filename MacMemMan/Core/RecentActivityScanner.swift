import Foundation

/// A dedicated, deep walk for Overview's "Last 24 Hours" card — deliberately independent of
/// whatever Junk/Large & Old/Duplicates happen to have scanned already, since relying on those
/// only surfaced files if you'd separately opened and scanned each of those sections first (which
/// under-counted badly in practice). This walks the same personal-content folders as "By File
/// Type" (`FileTypeAnalyzer.defaultRoots()`) — Documents, Desktop, Downloads, Pictures, Movies,
/// Music, Public — recursively, which is genuinely expensive on a large home folder, so callers
/// must trigger it explicitly rather than running it automatically.
enum RecentActivityScanner {
    static func scan(since cutoff: Date, roots: [URL] = FileTypeAnalyzer.defaultRoots()) -> [RecentFile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var results: [RecentFile] = []

        for root in roots {
            if Task.isCancelled { break }
            FileSystemScanner.walkFiles(root: root, filter: { entry in
                guard let modifiedAt = entry.modifiedAt else { return false }
                return modifiedAt >= cutoff
            }, onEntry: { entry in
                results.append(RecentFile(
                    path: entry.url.path,
                    displayName: entry.url.lastPathComponent,
                    sizeBytes: entry.sizeBytes,
                    modifiedAt: entry.modifiedAt ?? cutoff,
                    folder: root.path.hasPrefix(home.path) ? root.lastPathComponent : root.path
                ))
            })
        }

        return results.sorted { $0.modifiedAt > $1.modifiedAt }
    }
}
