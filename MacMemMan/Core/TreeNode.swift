import Foundation

/// One node in the on-demand storage tree. Children are loaded lazily the first time a node is
/// expanded (each child's recursive size is computed off the main thread via
/// `FileSystemScanner.immediateChildren`) so opening the tree never walks the whole disk up front.
@MainActor
final class TreeNode: ObservableObject, Identifiable {
    let url: URL
    /// `@Published` (not just mutable) so a background refresh can update an existing node's size
    /// in place — via `updateSize(_:status:)` — without discarding its already-loaded `children`,
    /// and have the row actually redraw when that happens.
    @Published private(set) var sizeBytes: Int64
    let modifiedAt: Date?
    let isDirectory: Bool
    /// Whether this node's own size was actually measured, or the read timed out — shown as a
    /// visible warning badge instead of a misleading "0 KB".
    @Published private(set) var sizeStatus: FileSystemScanner.SizeStatus

    @Published var children: [TreeNode]?
    @Published var isLoadingChildren = false
    /// True when this directory itself couldn't be listed at all (e.g. permission denied) — shown
    /// as an explicit error state instead of an indistinguishable "empty folder".
    @Published var listError = false

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    init(url: URL, sizeBytes: Int64, modifiedAt: Date?, isDirectory: Bool, sizeStatus: FileSystemScanner.SizeStatus = .ok) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.sizeStatus = sizeStatus
    }

    convenience init(entry: FileSystemScanner.Entry) {
        self.init(url: entry.url, sizeBytes: entry.sizeBytes, modifiedAt: entry.modifiedAt, isDirectory: entry.isDirectory, sizeStatus: entry.sizeStatus)
    }

    /// Root nodes start with an unknown (0) size — sizing the whole home folder up front is
    /// exactly the kind of synchronous, full-tree walk this view is designed to avoid. Once its
    /// children load, the root's size is approximated as their sum instead.
    static func root(_ url: URL) -> TreeNode {
        TreeNode(url: url, sizeBytes: 0, modifiedAt: nil, isDirectory: true)
    }

    func loadChildrenIfNeeded() async {
        guard isDirectory, children == nil, !isLoadingChildren else { return }
        isLoadingChildren = true
        defer { isLoadingChildren = false }

        let directoryURL = url
        let listing = await Task.detached { FileSystemScanner.immediateChildren(of: directoryURL) }.value

        guard listing.listable else {
            listError = true
            children = []
            return
        }

        listError = false
        let loaded = listing.entries
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .map { TreeNode(entry: $0) }
        children = loaded
        if sizeBytes == 0 {
            sizeBytes = loaded.reduce(0) { $0 + $1.sizeBytes }
        }
    }

    /// Discards whatever was loaded (or failed to load) so the next expand attempts again — used
    /// by the "Retry" affordance on timed-out or unreadable rows.
    func retry() {
        children = nil
        listError = false
        Task { await loadChildrenIfNeeded() }
    }

    /// Updates this node's own size/status in place — used when a background refresh re-measures
    /// an already-loaded node, so its `children` (and any expansion the user built up) survive.
    func updateSize(_ bytes: Int64, status: FileSystemScanner.SizeStatus) {
        sizeBytes = bytes
        sizeStatus = status
    }

    var asScanItem: ScanItem {
        ScanItem(
            path: url,
            category: .explorerSelection,
            reason: isDirectory ? "Folder" : "File",
            sizeBytes: sizeBytes,
            modifiedAt: modifiedAt,
            isDirectory: isDirectory
        )
    }
}
