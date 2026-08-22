import Foundation

/// A shared singleton, not a per-view `@StateObject` — like `OverviewViewModel`, Storage Explorer
/// is a conditional branch in `RootView`'s switch, and SwiftUI tears down `@StateObject`s in an
/// inactive branch. Without a persistent instance, every visit re-scanned Home from scratch and
/// threw away anything the user had expanded.
@MainActor
final class StorageTreeViewModel: ObservableObject {
    static let shared = StorageTreeViewModel()

    @Published var root: TreeNode
    @Published var selectedIDs: Set<String> = []
    @Published var isLoadingRoot = false
    @Published var isRefreshingRoot = false
    @Published private(set) var lastRootLoadDate: Date?

    private var selectedNodesByID: [String: TreeNode] = [:]
    private let minRefreshInterval: TimeInterval = 60

    private init(rootURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        root = .root(rootURL)
    }

    var selectedBytes: Int64 { selectedNodesByID.values.reduce(0) { $0 + $1.sizeBytes } }
    var selectedItems: [ScanItem] { selectedNodesByID.values.map(\.asScanItem) }

    func setRoot(_ url: URL) async {
        selectedIDs = []
        selectedNodesByID = [:]
        isLoadingRoot = true
        defer { isLoadingRoot = false }
        let node = TreeNode.root(url)
        await node.loadChildrenIfNeeded()
        root = node
        lastRootLoadDate = Date()
    }

    /// First call ever loads normally; after that, revisiting the tab keeps showing whatever's
    /// already loaded (labeled stale in the UI while this runs) and only re-measures the root's
    /// immediate children in the background — existing nodes are updated in place via
    /// `TreeNode.updateSize`, so any folder the user has already expanded stays expanded.
    func refreshRootIfStale(force: Bool = false) async {
        guard !isRefreshingRoot, !isLoadingRoot else { return }

        guard root.children != nil else {
            await root.loadChildrenIfNeeded()
            lastRootLoadDate = Date()
            return
        }

        if !force, let lastRootLoadDate, Date().timeIntervalSince(lastRootLoadDate) < minRefreshInterval {
            return
        }

        isRefreshingRoot = true
        defer { isRefreshingRoot = false }

        let directoryURL = root.url
        let listing = await Task.detached { FileSystemScanner.immediateChildren(of: directoryURL) }.value
        lastRootLoadDate = Date()
        guard listing.listable else { return } // keep showing the stale tree rather than clearing it

        mergeRootChildren(listing.entries)
    }

    private func mergeRootChildren(_ entries: [FileSystemScanner.Entry]) {
        var existingByPath = Dictionary(uniqueKeysWithValues: (root.children ?? []).map { ($0.url.path, $0) })

        let merged: [TreeNode] = entries
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .map { entry in
                if let existing = existingByPath.removeValue(forKey: entry.url.path) {
                    existing.updateSize(entry.sizeBytes, status: entry.sizeStatus)
                    return existing
                }
                return TreeNode(entry: entry)
            }

        root.children = merged
        root.updateSize(merged.reduce(0) { $0 + $1.sizeBytes }, status: .ok)

        // Anything left in existingByPath no longer exists on disk — drop its selection too.
        let removedIDs = Set(existingByPath.values.map(\.id))
        if !removedIDs.isEmpty {
            selectedIDs.subtract(removedIDs)
            for id in removedIDs { selectedNodesByID.removeValue(forKey: id) }
        }
    }

    func toggle(_ node: TreeNode) {
        if selectedIDs.contains(node.id) {
            selectedIDs.remove(node.id)
            selectedNodesByID.removeValue(forKey: node.id)
        } else {
            selectedIDs.insert(node.id)
            selectedNodesByID[node.id] = node
        }
    }

    func isSelected(_ node: TreeNode) -> Bool { selectedIDs.contains(node.id) }

    func clearSelection() {
        selectedIDs = []
        selectedNodesByID = [:]
    }
}
