import Foundation

/// One folder in the duplicates "By Folder" navigation mode — either a folder (with children) or
/// a leaf representing one file that's part of a duplicate set. Built fresh from `groups` whenever
/// they change; `List(_:children:)` renders it directly, no separate outline-state bookkeeping.
struct DuplicateTreeNode: Identifiable {
    let id: String
    let name: String
    let isFolder: Bool
    let totalBytes: Int64
    var children: [DuplicateTreeNode]?

    // Leaf-only:
    let item: ScanItem?
    let groupID: String?
    let isKeeper: Bool
    let copiesInGroup: Int
}

/// A shared singleton, not a per-view `@StateObject` — this screen is a conditional branch in
/// `RootView`'s switch, and SwiftUI tears down a `@StateObject` in an inactive branch. Without a
/// persistent instance, navigating away and back would lose the scan results and any selection,
/// forcing a full rescan every time.
@MainActor
final class DuplicatesViewModel: ObservableObject {
    static let shared = DuplicatesViewModel()
    private init() {
        // Seed from the last scan so this section shows real results the instant the app
        // launches, then quietly kick off one fresh scan in the background — `scan()` itself
        // leaves whatever's already on screen in place while it runs.
        if let cached = ScanCache.load([DuplicateFinder.DuplicateGroup].self, key: "duplicate_groups"), !cached.isEmpty {
            groups = cached
            hasScanned = true
            var toSelect: Set<String> = []
            for group in cached {
                for item in group.items.dropFirst() where item.safety.level != .personal {
                    toSelect.insert(item.id)
                }
            }
            selectedIDs = toSelect
            Task { await scan() }
        }
    }

    @Published var groups: [DuplicateFinder.DuplicateGroup] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    /// What's different from the previous scan — nil when this is the first scan ever, or when a
    /// rescan found no changes at all.
    @Published var lastChange: ScanChangeSummary?

    var wastedBytes: Int64 { groups.reduce(0) { $0 + $1.wastedBytes } }
    var selectedItems: [ScanItem] { groups.flatMap(\.items).filter { selectedIDs.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }

    /// The top-level scan root a path lives under (Downloads/Documents/Desktop) — shown as a small
    /// chip so it's immediately clear *where* a given copy actually is, without reading the full path.
    static func locationLabel(for path: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.path.hasPrefix(home) else { return "Home" }
        let relative = path.path.dropFirst(home.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.split(separator: "/").first.map(String.init) ?? "Home"
    }

    /// Rebuilds the folder tree fresh from `groups` — cheap enough (a few thousand items at most)
    /// that caching isn't worth the invalidation bugs it would invite.
    var tree: [DuplicateTreeNode] {
        let home = FileManager.default.homeDirectoryForCurrentUser

        final class MutableNode {
            let name: String
            let path: String
            var children: [String: MutableNode] = [:]
            var leaves: [DuplicateTreeNode] = []
            init(name: String, path: String) { self.name = name; self.path = path }
        }

        let root = MutableNode(name: "Home", path: home.path)

        for group in groups {
            for (index, item) in group.items.enumerated() {
                let folder = item.path.deletingLastPathComponent()
                let relative = folder.path.hasPrefix(home.path)
                    ? folder.path.dropFirst(home.path.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    : folder.path
                let components = relative.split(separator: "/").map(String.init)

                var current = root
                var runningPath = home.path
                for component in components {
                    runningPath += "/" + component
                    if let existing = current.children[component] {
                        current = existing
                    } else {
                        let node = MutableNode(name: component, path: runningPath)
                        current.children[component] = node
                        current = node
                    }
                }

                current.leaves.append(DuplicateTreeNode(
                    id: item.id, name: item.displayName, isFolder: false, totalBytes: item.sizeBytes, children: nil,
                    item: item, groupID: group.id, isKeeper: index == 0, copiesInGroup: group.items.count
                ))
            }
        }

        func freeze(_ node: MutableNode) -> DuplicateTreeNode {
            let folderChildren = node.children.values.map(freeze)
            let allChildren = (folderChildren + node.leaves).sorted { $0.totalBytes > $1.totalBytes }
            let total = allChildren.reduce(0) { $0 + $1.totalBytes }
            return DuplicateTreeNode(
                id: node.path, name: node.name, isFolder: true, totalBytes: total,
                children: allChildren.isEmpty ? nil : allChildren,
                item: nil, groupID: nil, isKeeper: false, copiesInGroup: 0
            )
        }

        return (root.children.values.map(freeze) + root.leaves)
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    /// Deliberately does not clear `groups`/`hasScanned` up front — see `JunkScanViewModel.scan()`
    /// for why: whatever's already on screen (cached or from a previous scan) stays visible while
    /// this runs, so a background refresh reads as "updating" rather than "starting over".
    func scan() async {
        isScanning = true
        let previousItems = groups.flatMap(\.items)
        let isRescan = hasScanned
        defer { isScanning = false; hasScanned = true }

        // Captured on the main actor before hopping to the background — `AppSettings` isn't safe
        // to reach into from `Task.detached`, so the roots are read here and passed in explicitly.
        let roots = AppSettings.shared.duplicateScanRoots
        let found = await Task.detached { DuplicateFinder.scan(options: DuplicateFinder.Options(roots: roots)) }.value
        groups = found
        ScanCache.save(groups, key: "duplicate_groups")

        // Pre-select every copy except the oldest ("keeper") in each group — but only when the
        // safety assessor doesn't consider the file personal (photos, videos, documents). Those
        // always require the user to opt in by hand, even though a duplicate technically exists.
        var toSelect: Set<String> = []
        for group in found {
            for item in group.items.dropFirst() where item.safety.level != .personal {
                toSelect.insert(item.id)
            }
        }
        selectedIDs = toSelect

        if isRescan {
            let change = ScanDiff.compute(old: previousItems, new: groups.flatMap(\.items))
            lastChange = change.hasChanges ? change : nil
        }
    }

    func toggle(_ item: ScanItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    /// Called after a successful delete with the ids of items actually removed. Drops just those
    /// items out of their groups — a group left with only one copy isn't a duplicate of anything
    /// anymore, so it's dropped entirely rather than shown as a "group" of one.
    func removeItems(withIDs ids: Set<String>) {
        groups = groups.compactMap { group in
            let remaining = group.items.filter { !ids.contains($0.id) }
            guard remaining.count > 1 else { return nil }
            return DuplicateFinder.DuplicateGroup(id: group.id, items: remaining)
        }
        selectedIDs.subtract(ids)
        ScanCache.save(groups, key: "duplicate_groups")
    }
}
