import Foundation

enum CompressionScanner {
    struct Options {
        var root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        var minSizeBytes: Int64 = 5 * 1024 * 1024 // 5 MB — below this, compression overhead isn't worth it
        var excludedPathComponents: Set<String> = ["Library", "node_modules", ".git", ".Trash"]
    }

    static func scan(options: Options) -> [CompressionCandidate] {
        var results: [CompressionCandidate] = []

        FileSystemScanner.walkFiles(root: options.root, filter: { entry in
            guard entry.sizeBytes >= options.minSizeBytes else { return false }
            let components = Set(entry.url.pathComponents)
            guard components.isDisjoint(with: options.excludedPathComponents) else { return false }
            return CompressionEstimator.estimatedSavingsFraction(forExtension: entry.url.pathExtension) != nil
        }, onEntry: { entry in
            let fraction = CompressionEstimator.estimatedSavingsFraction(forExtension: entry.url.pathExtension) ?? 0
            results.append(CompressionCandidate(
                path: entry.url,
                displayName: entry.url.lastPathComponent,
                sizeBytes: entry.sizeBytes,
                modifiedAt: entry.modifiedAt,
                estimatedSavingsFraction: fraction
            ))
        })

        return results.sorted { $0.estimatedSavingsBytes > $1.estimatedSavingsBytes }
    }
}
