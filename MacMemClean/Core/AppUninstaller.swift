import AppKit
import Foundation

enum AppUninstaller {
    static func installedApps() -> [AppInfo] {
        let fm = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]

        var apps: [AppInfo] = []
        for root in roots {
            guard let contents = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url) else { continue }
                let name = (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
                let size = FileSystemScanner.sizeOf(url)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let lastUsed = SpotlightMetadata.lastUsedDate(for: url)
                apps.append(AppInfo(
                    id: url.path,
                    bundlePath: url,
                    bundleIdentifier: bundle.bundleIdentifier,
                    name: name,
                    version: version,
                    sizeBytes: size,
                    icon: icon,
                    lastUsedDate: lastUsed
                ))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Finds files/folders elsewhere on disk that "belong" to this app, matched by bundle
    /// identifier and, as a fallback, by app name.
    static func leftoverPlan(for app: AppInfo) -> UninstallPlan {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var items: [ScanItem] = []

        let appItem = ScanItem(
            path: app.bundlePath,
            category: .appLeftovers,
            reason: "Application bundle",
            sizeBytes: app.sizeBytes,
            modifiedAt: nil,
            isDirectory: true,
            groupKey: app.id
        )
        items.append(appItem)

        let idCandidates = [app.bundleIdentifier].compactMap { $0 }
        let nameCandidates = [app.name]

        let searchRoots: [(URL, String)] = [
            (home.appendingPathComponent("Library/Application Support"), "Application Support"),
            (home.appendingPathComponent("Library/Caches"), "Cache"),
            (home.appendingPathComponent("Library/Preferences"), "Preferences"),
            (home.appendingPathComponent("Library/Saved Application State"), "Saved State"),
            (home.appendingPathComponent("Library/Logs"), "Logs"),
            (home.appendingPathComponent("Library/Containers"), "Container"),
            (home.appendingPathComponent("Library/Group Containers"), "Group Container"),
            (home.appendingPathComponent("Library/HTTPStorages"), "HTTP Storage"),
            (home.appendingPathComponent("Library/WebKit"), "WebKit Data"),
        ]

        for (root, label) in searchRoots {
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]) else { continue }
            for child in children {
                let stem = child.lastPathComponent
                let matchesID = idCandidates.contains { stem.hasPrefix($0) || stem == "\($0).plist" }
                let matchesName = nameCandidates.contains { stem.localizedCaseInsensitiveContains($0) }
                guard matchesID || matchesName else { continue }

                let values = try? child.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
                let isDir = values?.isDirectory ?? false
                let size = isDir ? FileSystemScanner.sizeOf(child) : Int64((try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                guard size > 0 else { continue }

                items.append(ScanItem(
                    path: child,
                    category: .appLeftovers,
                    reason: label,
                    sizeBytes: size,
                    modifiedAt: values?.contentModificationDate,
                    isDirectory: isDir,
                    groupKey: app.id
                ))
            }
        }

        return UninstallPlan(app: app, items: items)
    }
}
