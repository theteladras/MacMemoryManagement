import CryptoKit
import Foundation

enum DuplicateFinder {
    struct DuplicateGroup: Identifiable, Codable {
        let id: String // hash
        let items: [ScanItem] // sorted oldest first; caller pre-selects all but items[0] to remove
        var sizeEach: Int64 { items.first?.sizeBytes ?? 0 }
        var wastedBytes: Int64 { sizeEach * Int64(items.count - 1) }
    }

    struct Options {
        var roots: [URL] = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
        ]
        var minSizeBytes: Int64 = 1024 * 100 // ignore tiny files, too many false-positive-prone dupes
    }

    static func scan(options: Options) -> [DuplicateGroup] {
        var bySize: [Int64: [URL]] = [:]

        for root in options.roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            FileSystemScanner.walkFiles(root: root, filter: { $0.sizeBytes >= options.minSizeBytes }, onEntry: { entry in
                bySize[entry.sizeBytes, default: []].append(entry.url)
            })
        }

        var groups: [DuplicateGroup] = []

        for (size, urls) in bySize where urls.count > 1 {
            if Task.isCancelled { break }
            var byHash: [String: [URL]] = [:]
            for url in urls {
                guard let hash = sha256(of: url) else { continue }
                byHash[hash, default: []].append(url)
            }

            for (hash, matchingURLs) in byHash where matchingURLs.count > 1 {
                let items = matchingURLs.compactMap { url -> ScanItem? in
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    return ScanItem(path: url, category: .duplicates, reason: "Duplicate (\(matchingURLs.count) copies)", sizeBytes: size, modifiedAt: values?.contentModificationDate, isDirectory: false, groupKey: hash)
                }.sorted { ($0.modifiedAt ?? .distantPast) < ($1.modifiedAt ?? .distantPast) }

                guard items.count > 1 else { continue }
                groups.append(DuplicateGroup(id: hash, items: items))
            }
        }

        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    /// Hashes only the first 4MB for files larger than that as a fast approximation once files already
    /// match on exact size — collisions across distinct large files with an identical size AND identical
    /// first 4MB are vanishingly unlikely in this personal-files context.
    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024
        var totalRead = 0
        let cap = 4 * 1024 * 1024

        while totalRead < cap {
            guard let data = try? handle.read(upToCount: chunkSize), !data.isEmpty else { break }
            hasher.update(data: data)
            totalRead += data.count
        }

        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
