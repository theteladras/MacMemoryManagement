import AppKit
import Foundation

/// The only place in the app that ever calls a delete API. Every path is
/// re-validated against `ProtectedPaths` and re-checked for existence
/// immediately before it is removed, independent of whatever the originating
/// scan found — scan results can go stale between the scan and the user's
/// confirmation.
enum SafeDeleteService {
    /// Re-statting and removing every item (especially re-computing folder sizes) is real disk
    /// I/O, so — like every scanner in the app — this must never run inline on the caller's
    /// executor (the Review Sheet calls this from the main actor). `Task.detached` is what
    /// actually moves the work off the main thread.
    static func delete(_ items: [ScanItem], mode: DeleteMode) async -> DeleteResult {
        await Task.detached {
            var result = DeleteResult()

            for item in items {
                if Task.isCancelled { break }

                if let reason = ProtectedPaths.blockReason(for: item.path) {
                    result.failed.append((item, reason))
                    continue
                }
                guard FileManager.default.fileExists(atPath: item.path.path) else {
                    result.failed.append((item, "No longer exists"))
                    continue
                }

                let freshSize = FileSystemScanner.sizeOf(item.path)

                do {
                    var trashedURL: URL?
                    switch mode {
                    case .trash:
                        trashedURL = try moveToTrash(item.path)
                    case .permanent:
                        try FileManager.default.removeItem(at: item.path)
                    }
                    result.successes.append(DeleteResult.Success(item: item, trashedURL: trashedURL))
                    result.freedBytes += freshSize
                } catch {
                    result.failed.append((item, error.localizedDescription))
                }
            }

            return result
        }.value
    }

    @discardableResult
    private static func moveToTrash(_ url: URL) throws -> URL? {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }
}
