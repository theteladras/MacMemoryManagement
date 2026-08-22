import Foundation

/// One row in the permanent deletion history — recorded the moment `SafeDeleteService` actually
/// removes something, so it survives even after the on-screen scan results are gone.
struct DeletionLogEntry: Identifiable, Codable {
    enum Outcome: Codable, Equatable {
        case deleted
        case failed(String)
    }

    let id: UUID
    let date: Date
    let operationTitle: String
    let path: String
    let displayName: String
    let category: ScanCategory
    let sizeBytes: Int64
    let mode: DeleteMode
    let outcome: Outcome
    /// Where the item landed in the Trash, if known and mode was `.trash` — lets History offer
    /// "Reveal in Finder" for items that are still recoverable.
    let trashedPath: String?

    init(operationTitle: String, item: ScanItem, mode: DeleteMode, outcome: Outcome, trashedPath: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.operationTitle = operationTitle
        self.path = item.path.path
        self.displayName = item.displayName
        self.category = item.category
        self.sizeBytes = item.sizeBytes
        self.mode = mode
        self.outcome = outcome
        self.trashedPath = trashedPath
    }
}
