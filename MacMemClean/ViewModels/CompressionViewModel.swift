import Foundation

@MainActor
final class CompressionViewModel: ObservableObject {
    @Published var candidates: [CompressionCandidate] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var scanRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    @Published var minSizeMB: Double = 5

    @Published var isCompressing = false
    @Published var progress: (done: Int, total: Int) = (0, 0)
    @Published var result: CompressionService.Result?

    var selectedCandidates: [CompressionCandidate] { candidates.filter { selectedIDs.contains($0.id) } }
    var selectedEstimatedSavings: Int64 { selectedCandidates.reduce(0) { $0 + $1.estimatedSavingsBytes } }

    func scan() async {
        isScanning = true
        hasScanned = false
        candidates = []
        selectedIDs = []
        result = nil
        defer { isScanning = false; hasScanned = true }

        let root = scanRoot
        let minSize = Int64(minSizeMB * 1024 * 1024)
        candidates = await Task.detached {
            var options = CompressionScanner.Options()
            options.root = root
            options.minSizeBytes = minSize
            return CompressionScanner.scan(options: options)
        }.value

        // Compression is lossless and verified byte-for-byte before anything is replaced, so
        // — unlike deletion — it's safe to default to selecting everything found.
        selectedIDs = Set(candidates.map(\.id))
    }

    func toggle(_ candidate: CompressionCandidate) {
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
        } else {
            selectedIDs.insert(candidate.id)
        }
    }

    func selectAll() { selectedIDs = Set(candidates.map(\.id)) }
    func selectNone() { selectedIDs = [] }

    func compressSelected() async {
        isCompressing = true
        progress = (0, selectedCandidates.count)
        defer { isCompressing = false }

        let items = selectedCandidates
        let outcome = await CompressionService.compress(items) { [weak self] done, total in
            Task { @MainActor in self?.progress = (done, total) }
        }
        result = outcome

        let doneIDs = Set(outcome.successes.map { $0.candidate.id })
        candidates.removeAll { doneIDs.contains($0.id) }
        selectedIDs.subtract(doneIDs)
    }
}
