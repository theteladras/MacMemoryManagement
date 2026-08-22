import SwiftUI

enum DiskUsageAnalyzer {
    static func summary() -> DiskUsageSummary {
        var summary = DiskUsageSummary()

        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            summary.totalBytes = Int64(values.volumeTotalCapacity ?? 0)
            summary.freeBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        }

        summary.breakdown = topLevelBreakdown()
        return summary
    }

    /// Best-effort category breakdown, similar in spirit to Finder's "About This Mac" storage view.
    /// This intentionally does not walk every file on disk (far too slow) — it sizes a handful of
    /// well-known top-level roots and buckets everything else as "Other".
    private static func topLevelBreakdown() -> [DiskCategoryUsage] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default

        func size(_ url: URL) -> Int64 {
            guard fm.fileExists(atPath: url.path) else { return 0 }
            return FileSystemScanner.sizeOf(url)
        }

        let applications = size(URL(fileURLWithPath: "/Applications"))
        let documents = size(home.appendingPathComponent("Documents"))
        let desktop = size(home.appendingPathComponent("Desktop"))
        let downloads = size(home.appendingPathComponent("Downloads"))
        let photosMovies = size(home.appendingPathComponent("Pictures")) + size(home.appendingPathComponent("Movies")) + size(home.appendingPathComponent("Music"))
        let library = size(home.appendingPathComponent("Library"))

        return [
            DiskCategoryUsage(name: "Applications", symbolName: "square.grid.2x2", bytes: applications, tint: .purple),
            DiskCategoryUsage(name: "Documents & Desktop", symbolName: "doc.on.doc", bytes: documents + desktop, tint: .indigo),
            DiskCategoryUsage(name: "Downloads", symbolName: "arrow.down.circle", bytes: downloads, tint: .teal),
            DiskCategoryUsage(name: "Photos, Movies & Music", symbolName: "photo.on.rectangle", bytes: photosMovies, tint: .pink),
            DiskCategoryUsage(name: "System & Library", symbolName: "gearshape", bytes: library, tint: .orange),
        ].filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
    }

    /// One level deeper into a top-level category — "what's inside Documents & Desktop", "what's
    /// inside Library". Returns nil for categories that don't have a meaningful further split
    /// ("Other", "Free"). Each drill-down still only sizes a bounded, known set of locations, same
    /// discipline as the top-level breakdown.
    static func drillDown(for categoryName: String) -> [DiskCategoryUsage]? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        switch categoryName {
        case "Applications":
            return topItemsBySize(root: URL(fileURLWithPath: "/Applications"), tint: .purple, limit: 8)
        case "Documents & Desktop":
            return namedFolders([
                ("Documents", home.appendingPathComponent("Documents")),
                ("Desktop", home.appendingPathComponent("Desktop")),
            ], tint: .indigo)
        case "Downloads":
            return topItemsBySize(root: home.appendingPathComponent("Downloads"), tint: .teal, limit: 8)
        case "Photos, Movies & Music":
            return namedFolders([
                ("Pictures", home.appendingPathComponent("Pictures")),
                ("Movies", home.appendingPathComponent("Movies")),
                ("Music", home.appendingPathComponent("Music")),
            ], tint: .pink)
        case "System & Library":
            return topItemsBySize(root: home.appendingPathComponent("Library"), tint: .orange, limit: 8)
        default:
            return nil
        }
    }

    /// Sizes each named folder directly — used for categories that are already a fixed, small set
    /// of known folders (e.g. Documents & Desktop → those two).
    private static func namedFolders(_ folders: [(name: String, url: URL)], tint: Color) -> [DiskCategoryUsage] {
        let fm = FileManager.default
        return folders.compactMap { name, url -> DiskCategoryUsage? in
            guard fm.fileExists(atPath: url.path) else { return nil }
            let bytes = FileSystemScanner.sizeOf(url)
            guard bytes > 0 else { return nil }
            return DiskCategoryUsage(name: name, symbolName: "folder.fill", bytes: bytes, tint: tint)
        }.sorted { $0.bytes > $1.bytes }
    }

    /// Immediate children of a folder, largest first, capped to `limit` with everything else
    /// bucketed into a single "Other" entry so the drill-down bar still sums to the parent's total.
    private static func topItemsBySize(root: URL, tint: Color, limit: Int) -> [DiskCategoryUsage]? {
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        let entries = FileSystemScanner.immediateChildren(of: root).entries
            .filter { $0.sizeBytes > 0 }
            .sorted { $0.sizeBytes > $1.sizeBytes }
        guard !entries.isEmpty else { return nil }

        var items = entries.prefix(limit).map {
            DiskCategoryUsage(name: $0.url.lastPathComponent, symbolName: $0.isDirectory ? "folder.fill" : "doc.fill", bytes: $0.sizeBytes, tint: tint)
        }
        let restBytes = entries.dropFirst(limit).reduce(0) { $0 + $1.sizeBytes }
        if restBytes > 0 {
            items.append(DiskCategoryUsage(name: "Other", symbolName: "ellipsis", bytes: restBytes, tint: .gray))
        }
        return items
    }
}
