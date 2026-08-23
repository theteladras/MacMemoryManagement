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

        let paths: [(key: String, url: URL)] = [
            ("applications", URL(fileURLWithPath: "/Applications")),
            ("documents", home.appendingPathComponent("Documents")),
            ("desktop", home.appendingPathComponent("Desktop")),
            ("downloads", home.appendingPathComponent("Downloads")),
            ("pictures", home.appendingPathComponent("Pictures")),
            ("movies", home.appendingPathComponent("Movies")),
            ("music", home.appendingPathComponent("Music")),
            ("library", home.appendingPathComponent("Library")),
        ]

        // Sized in parallel, with a longer-than-default timeout: measured directly on a real
        // machine, `/Applications` alone routinely takes 8-11s to `du` — already past the
        // framework's normal 6s cap regardless of parallelism, which is exactly what was making it
        // (and borderline ones like ~/Library, ~/Desktop) silently drop out of the breakdown and
        // inflate "Other" with no explanation. This runs off the main thread in a background
        // refresh (Overview shows cached numbers while it's in flight), so it can afford to wait.
        let results = ThreadSafeBox<[String: Int64]>([:])
        DispatchQueue.concurrentPerform(iterations: paths.count) { index in
            let (key, url) = paths[index]
            guard fm.fileExists(atPath: url.path) else { return }
            let bytes = FileSystemScanner.sizeOf(url, timeout: 20)
            results.mutate { $0[key] = bytes }
        }
        let sizes = results.value

        let applications = sizes["applications"] ?? 0
        let documents = sizes["documents"] ?? 0
        let desktop = sizes["desktop"] ?? 0
        let downloads = sizes["downloads"] ?? 0
        let photosMovies = (sizes["pictures"] ?? 0) + (sizes["movies"] ?? 0) + (sizes["music"] ?? 0)
        let library = sizes["library"] ?? 0

        return [
            DiskCategoryUsage(name: "Applications", symbolName: "square.grid.2x2", bytes: applications, tint: .purple),
            DiskCategoryUsage(name: "Documents & Desktop", symbolName: "doc.on.doc", bytes: documents + desktop, tint: .indigo),
            DiskCategoryUsage(name: "Downloads", symbolName: "arrow.down.circle", bytes: downloads, tint: .teal),
            DiskCategoryUsage(name: "Photos, Movies & Music", symbolName: "photo.on.rectangle", bytes: photosMovies, tint: .pink),
            DiskCategoryUsage(name: "System & Library", symbolName: "gearshape", bytes: library, tint: .orange),
        ].filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
    }

    /// One level deeper into a top-level category — "what's inside Documents & Desktop", "what's
    /// inside Library". Each drill-down still only sizes a bounded, known set of locations, same
    /// discipline as the top-level breakdown. `otherTotalBytes` is only used for the "Other"
    /// category, which — unlike the rest — isn't a single known folder, so it needs the parent
    /// total to figure out how much of it is accounted for versus genuinely outside the home
    /// folder. Returns nil only for "Free", which has nothing to drill into.
    static func drillDown(for categoryName: String, otherTotalBytes: Int64 = 0) -> [DiskCategoryUsage]? {
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
        case "Other":
            return otherBreakdown(totalOtherBytes: otherTotalBytes)
        default:
            return nil
        }
    }

    /// "Other" isn't one folder — it's whatever's left after subtracting the named categories from
    /// total used space. The one part of that we actually *can* itemize is hidden top-level items
    /// in the home folder that the main breakdown never looks at (`.cache`, `.npm`, `.docker`,
    /// `.Trash`, dev tool caches, etc. — anything not named Documents/Desktop/Downloads/Pictures/
    /// Movies/Music/Library). Whatever's left after that is genuinely outside the home folder
    /// (system volume, other users, snapshots, swap) and gets a single honest "System-wide" line
    /// rather than a fake-precise breakdown we can't actually produce without root access.
    private static func otherBreakdown(totalOtherBytes: Int64) -> [DiskCategoryUsage]? {
        guard totalOtherBytes > 0 else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let alreadyCounted: Set<String> = ["Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Library"]

        let entries = FileSystemScanner.immediateChildren(of: home, includeHidden: true).entries
            .filter { !alreadyCounted.contains($0.url.lastPathComponent) && $0.sizeBytes > 0 }
            .sorted { $0.sizeBytes > $1.sizeBytes }

        var items = entries.prefix(8).map {
            DiskCategoryUsage(name: $0.url.lastPathComponent, symbolName: $0.isDirectory ? "folder.fill" : "doc.fill", bytes: $0.sizeBytes, tint: .gray)
        }
        let homeExtrasTotal = entries.reduce(0) { $0 + $1.sizeBytes }
        let restOfHomeExtras = entries.dropFirst(8).reduce(0) { $0 + $1.sizeBytes }
        if restOfHomeExtras > 0 {
            items.append(DiskCategoryUsage(name: "Other Home Files", symbolName: "ellipsis", bytes: restOfHomeExtras, tint: Color.gray.opacity(0.7)))
        }

        let systemWide = max(0, totalOtherBytes - homeExtrasTotal)
        if systemWide > 0 {
            items.append(DiskCategoryUsage(
                name: "System-wide (outside your home folder)",
                symbolName: "gearshape.2",
                bytes: systemWide,
                tint: .secondary
            ))
        }

        return items.isEmpty ? nil : items
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
