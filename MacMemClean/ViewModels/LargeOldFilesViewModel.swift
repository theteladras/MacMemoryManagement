import Foundation

@MainActor
final class LargeOldFilesViewModel: ObservableObject {
    @Published var largeItems: [ScanItem] = []
    @Published var oldItems: [ScanItem] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var minSizeMB: Double = 100
    @Published var minAgeDays: Int = 180
    @Published var scanRoot: URL = FileManager.default.homeDirectoryForCurrentUser

    var allItems: [ScanItem] { largeItems + oldItems }
    var selectedItems: [ScanItem] { allItems.filter { selectedIDs.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }

    func scan() async {
        isScanning = true
        hasScanned = false
        largeItems = []
        oldItems = []
        selectedIDs = []
        defer { isScanning = false; hasScanned = true }

        let root = scanRoot
        let minSize = Int64(minSizeMB * 1024 * 1024)
        let minAge = minAgeDays

        let result = await Task.detached {
            var options = LargeOldFilesScanner.Options()
            options.root = root
            options.minSizeBytes = minSize
            options.minAgeDays = minAge
            return LargeOldFilesScanner.scan(options: options)
        }.value
        largeItems = result.large
        oldItems = result.old
    }

    func toggle(_ item: ScanItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func removeFromResults(_ items: [ScanItem]) {
        let ids = Set(items.map(\.id))
        largeItems.removeAll { ids.contains($0.id) }
        oldItems.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
    }
}
