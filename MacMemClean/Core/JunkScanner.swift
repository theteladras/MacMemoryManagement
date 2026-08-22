import Foundation

/// Scans a declarative catalog of well-known cache/log/temp locations.
/// Read-only — produces `ScanItem`s only.
enum JunkScanner {
    struct Location {
        let root: URL
        let category: ScanCategory
        let label: String
        /// If true, each immediate child of `root` becomes its own ScanItem (e.g. one per app's cache
        /// folder). If false, `root` itself becomes a single ScanItem.
        let listChildren: Bool
    }

    private static let fm = FileManager.default
    private static var home: URL { fm.homeDirectoryForCurrentUser }

    static func knownLocations() -> [Location] {
        var locations: [Location] = [
            Location(root: home.appendingPathComponent("Library/Caches"), category: .userCaches, label: "App Caches", listChildren: true),
            Location(root: home.appendingPathComponent("Library/Logs"), category: .logs, label: "User Logs", listChildren: true),
            Location(root: URL(fileURLWithPath: "/Library/Logs"), category: .logs, label: "System Logs", listChildren: true),
            Location(root: home.appendingPathComponent(".Trash"), category: .trash, label: "Trash", listChildren: true),
        ]

        let browserCaches: [(String, String)] = [
            ("Library/Caches/com.apple.Safari", "Safari"),
            ("Library/Caches/Google/Chrome", "Chrome"),
            ("Library/Caches/BraveSoftware", "Brave"),
            ("Library/Caches/Firefox", "Firefox"),
            ("Library/Caches/com.microsoft.edgemac", "Edge"),
        ]
        for (relativePath, name) in browserCaches {
            locations.append(Location(root: home.appendingPathComponent(relativePath), category: .browserCaches, label: "\(name) Cache", listChildren: false))
        }

        let developerLocations: [(String, String)] = [
            ("Library/Developer/Xcode/DerivedData", "Xcode DerivedData"),
            ("Library/Developer/Xcode/Archives", "Xcode Archives"),
            ("Library/Developer/CoreSimulator/Caches", "Simulator Caches"),
        ]
        for (relativePath, _) in developerLocations {
            locations.append(Location(root: home.appendingPathComponent(relativePath), category: .developerJunk, label: "Developer Junk", listChildren: true))
        }

        return locations
    }

    /// Runs the full catalog, reporting coarse progress via `onLocation` as each root finishes.
    static func scan(onLocation: @escaping (String) -> Void = { _ in }) -> [ScanItem] {
        var items: [ScanItem] = []

        for location in knownLocations() {
            if Task.isCancelled { break }
            guard fm.fileExists(atPath: location.root.path) else { continue }
            onLocation(location.label)

            if location.listChildren {
                for entry in FileSystemScanner.immediateChildren(of: location.root).entries {
                    guard entry.sizeBytes > 0 else { continue }
                    items.append(ScanItem(
                        path: entry.url,
                        category: location.category,
                        reason: location.label,
                        sizeBytes: entry.sizeBytes,
                        modifiedAt: entry.modifiedAt,
                        isDirectory: entry.isDirectory
                    ))
                }
            } else {
                let size = FileSystemScanner.sizeOf(location.root)
                guard size > 0 else { continue }
                let values = try? location.root.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
                items.append(ScanItem(
                    path: location.root,
                    category: location.category,
                    reason: location.label,
                    sizeBytes: size,
                    modifiedAt: values?.contentModificationDate,
                    isDirectory: values?.isDirectory ?? true
                ))
            }
        }

        return items
    }
}
