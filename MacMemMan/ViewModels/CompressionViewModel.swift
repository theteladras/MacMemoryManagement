import Foundation

/// A shared singleton, not a per-view `@StateObject` — see `LargeOldFilesViewModel` for why.
@MainActor
final class CompressionViewModel: ObservableObject {
    static let shared = CompressionViewModel()
    private init() {
        // Remember the last folder the user explicitly chose, so returning users don't have to
        // re-pick it every launch — but there's still no *default* on first use (see `scanRoot`).
        if let storedPath = UserDefaults.standard.string(forKey: Keys.scanRoot) {
            scanRoot = URL(fileURLWithPath: storedPath)
        }
        // Seed from the last scan so this section shows real results the instant the app
        // launches, then quietly kick off one fresh scan in the background — `scan()` itself
        // leaves whatever's already on screen in place while it runs.
        if let cached = ScanCache.load([CompressionCandidate].self, key: "compression_candidates"), !cached.isEmpty {
            candidates = cached
            hasScanned = true
            selectedIDs = Set(cached.map(\.id))
            if scanRoot != nil {
                Task { await scan() }
            }
        }
    }

    private enum Keys {
        static let scanRoot = "compression.scanRoot"
    }

    @Published var candidates: [CompressionCandidate] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    /// No default location — unlike `LargeOldFilesViewModel`, this starts `nil` so the user has to
    /// explicitly pick a folder to analyze rather than silently getting scanned results for a
    /// folder ("Documents") they never chose.
    @Published var scanRoot: URL? {
        didSet {
            if let scanRoot {
                UserDefaults.standard.set(scanRoot.path, forKey: Keys.scanRoot)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.scanRoot)
            }
        }
    }
    @Published var minSizeMB: Double = 5

    @Published var isCompressing = false
    @Published var progress: (done: Int, total: Int) = (0, 0)
    @Published var result: CompressionService.Result?
    /// What's different from the previous scan — nil when this is the first scan ever, or when a
    /// rescan found no changes at all.
    @Published var lastChange: ScanChangeSummary?

    var selectedCandidates: [CompressionCandidate] { candidates.filter { selectedIDs.contains($0.id) } }
    var selectedEstimatedSavings: Int64 { selectedCandidates.reduce(0) { $0 + $1.estimatedSavingsBytes } }

    /// Deliberately does not clear `candidates`/`hasScanned` up front — see
    /// `JunkScanViewModel.scan()` for why: whatever's already on screen (cached or from a
    /// previous scan) stays visible while this runs, so a background refresh reads as "updating"
    /// rather than "starting over".
    func scan() async {
        guard let root = scanRoot else { return }
        isScanning = true
        result = nil
        let previousCandidates = candidates
        let isRescan = hasScanned
        defer { isScanning = false; hasScanned = true }

        let minSize = Int64(minSizeMB * 1024 * 1024)
        candidates = await Task.detached {
            var options = CompressionScanner.Options()
            options.root = root
            options.minSizeBytes = minSize
            return CompressionScanner.scan(options: options)
        }.value
        ScanCache.save(candidates, key: "compression_candidates")

        // Compression is lossless and verified byte-for-byte before anything is replaced, so
        // — unlike deletion — it's safe to default to selecting everything found.
        selectedIDs = Set(candidates.map(\.id))

        if isRescan {
            let change = ScanDiff.compute(old: previousCandidates, new: candidates)
            lastChange = change.hasChanges ? change : nil
        }
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
        ScanCache.save(candidates, key: "compression_candidates")
    }
}
