import Foundation

@MainActor
final class DuplicatesViewModel: ObservableObject {
    @Published var groups: [DuplicateFinder.DuplicateGroup] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var hasScanned = false

    var wastedBytes: Int64 { groups.reduce(0) { $0 + $1.wastedBytes } }
    var selectedItems: [ScanItem] { groups.flatMap(\.items).filter { selectedIDs.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }

    func scan() async {
        isScanning = true
        hasScanned = false
        groups = []
        selectedIDs = []
        defer { isScanning = false; hasScanned = true }

        let found = await Task.detached { DuplicateFinder.scan(options: .init()) }.value
        groups = found

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
    }

    func toggle(_ item: ScanItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func removeGroups(withIDs ids: Set<String>) {
        groups.removeAll { ids.contains($0.id) }
        let itemIDs = Set(groups.flatMap(\.items).map(\.id))
        selectedIDs.formIntersection(itemIDs)
    }
}
