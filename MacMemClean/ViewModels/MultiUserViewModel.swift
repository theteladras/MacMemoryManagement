import Foundation

/// A shared singleton, not a per-view `@StateObject` — see `LargeOldFilesViewModel` for why.
@MainActor
final class MultiUserViewModel: ObservableObject {
    static let shared = MultiUserViewModel()
    private init() {}

    @Published var accounts: [OtherUserAccount] = []
    @Published var hasLoadedAccounts = false
    @Published var accountSizes: [String: Int64] = [:]
    @Published var isLoadingSizes = false

    @Published var selectedAccount: OtherUserAccount?
    @Published var items: [ScanItem] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var lastError: String?
    /// What's different from the previous scan of *this same* account — nil the first time an
    /// account is scanned, when switching to a different account, or when a rescan found nothing
    /// new.
    @Published var lastChange: ScanChangeSummary?

    var selectedItems: [ScanItem] { items.filter { selectedIDs.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }

    /// No admin needed — just enumerates account names via `dscl`.
    func loadAccounts() {
        accounts = MultiUserScanner.listOtherUsers()
        hasLoadedAccounts = true
    }

    /// One admin prompt sizes every account at once.
    func loadSizes() async {
        guard !accounts.isEmpty else { return }
        isLoadingSizes = true
        lastError = nil
        defer { isLoadingSizes = false }
        do {
            accountSizes = try await MultiUserScanner.homeSizes(for: accounts)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func scanJunk(for account: OtherUserAccount) async {
        let isRescanOfSameAccount = hasScanned && selectedAccount?.username == account.username
        let previousItems = isRescanOfSameAccount ? items : []

        selectedAccount = account
        isScanning = true
        hasScanned = false
        items = []
        // Never pre-selected, unlike every other scanner's "Safe" items — this belongs to a
        // different account, so it always requires the user to opt in by hand, item by item.
        selectedIDs = []
        lastError = nil
        lastChange = nil
        defer { isScanning = false; hasScanned = true }
        do {
            items = try await MultiUserScanner.scanJunk(for: account)
            if isRescanOfSameAccount {
                let change = ScanDiff.compute(old: previousItems, new: items)
                lastChange = change.hasChanges ? change : nil
            }
        } catch {
            lastError = error.localizedDescription
        }
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

    func removeFromResults(_ deletedItems: [ScanItem]) {
        let ids = Set(deletedItems.map(\.id))
        items.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
    }
}
