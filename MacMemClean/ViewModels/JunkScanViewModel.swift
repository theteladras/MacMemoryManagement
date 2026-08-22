import Foundation

@MainActor
final class JunkScanViewModel: ObservableObject {
    @Published var items: [ScanItem] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var statusText = ""
    @Published var hasScanned = false

    var selectedItems: [ScanItem] { items.filter { selectedIDs.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }

    func scan() async {
        isScanning = true
        hasScanned = false
        items = []
        selectedIDs = []
        statusText = "Scanning known cache, log & junk locations…"
        defer { isScanning = false; hasScanned = true }

        let found = await Task.detached { JunkScanner.scan() }.value

        items = found.sorted { $0.sizeBytes > $1.sizeBytes }
        // Only pre-select items the safety assessor is confident are disposable. Anything it
        // flagged caution/personal (or that needs Full Disk Access to have been scanned reliably)
        // is left unchecked so the user opts in deliberately.
        selectedIDs = Set(items.filter { $0.safety.level.autoSelectByDefault && !$0.category.requiresFullDiskAccess }.map(\.id))
    }

    func toggle(_ item: ScanItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectAll() { selectedIDs = Set(items.map(\.id)) }
    func selectNone() { selectedIDs = [] }

    func removeFromResults(_ items: [ScanItem]) {
        let ids = Set(items.map(\.id))
        self.items.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
    }
}
