import Foundation

/// Low-level recursive filesystem walking primitives shared by all scanners.
/// Everything here is read-only.
enum FileSystemScanner {
    /// Whether a size was actually measured, or the read gave up — surfaced to the UI so a stuck
    /// read shows up as a visible warning instead of a silently-wrong "0 KB" or a spinner with no
    /// explanation.
    enum SizeStatus: Equatable {
        case ok
        case timedOut
    }

    struct Entry {
        let url: URL
        let sizeBytes: Int64
        let modifiedAt: Date?
        let isDirectory: Bool
        let sizeStatus: SizeStatus
    }

    /// Result of listing a directory's immediate children: the entries found, and whether the
    /// listing itself succeeded (as opposed to e.g. a permission error on the directory itself).
    struct DirectoryListing {
        let entries: [Entry]
        let listable: Bool
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey,
    ]

    /// Computes the total on-disk size of a single file or directory (recursive).
    /// Directories go through `/usr/bin/du`, which is dramatically faster than walking every file
    /// via `FileManager` (it's optimized C doing raw `stat()` calls, not allocating a Swift/Foundation
    /// object per file) — the difference between a tree browser that opens instantly and one that
    /// looks permanently stuck on folders like `~/Library`. Falls back to the enumerator if `du`
    /// is ever unavailable.
    static func sizeOf(_ url: URL, timeout: TimeInterval = duTimeoutSeconds) -> Int64 {
        sizeAndStatus(of: url, timeout: timeout).0
    }

    static func sizeAndStatus(of url: URL, timeout: TimeInterval = duTimeoutSeconds) -> (Int64, SizeStatus) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return (0, .ok) }

        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return (Int64(values?.fileSize ?? 0), .ok)
        }

        switch duSize(of: url, timeout: timeout) {
        case .value(let bytes):
            return (bytes, .ok)
        case .timedOut:
            // Falling back to the in-process enumerator here would hit the exact same block (most
            // likely a stuck TCC permission dialog for this folder) — so don't retry, just report
            // this one folder as unreadable-for-now and let the rest of the scan carry on.
            return (0, .timedOut)
        case .processUnavailable:
            return (enumeratedSize(of: url), .ok)
        }
    }

    private enum DuResult {
        case value(Int64)
        case timedOut
        case processUnavailable
    }

    /// Hard ceiling on a single `du` call. Without Full Disk Access, the very first time the app
    /// touches a TCC-protected folder (Desktop/Documents/Downloads) macOS can show a blocking
    /// system permission alert — if that dialog isn't answered promptly, the read blocks
    /// indefinitely. This timeout guarantees the scan itself can never hang forever regardless of
    /// the cause; the folder just gets reported as unreadable and the rest of the scan continues.
    static let duTimeoutSeconds: TimeInterval = 6

    private static func duSize(of url: URL, timeout: TimeInterval) -> DuResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe() // discard "Permission denied" noise on protected subfolders

        let doneSignal = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in doneSignal.signal() }

        do {
            try process.run()
        } catch {
            return .processUnavailable
        }

        guard doneSignal.wait(timeout: .now() + timeout) == .success else {
            process.terminationHandler = nil
            process.terminate()
            return .timedOut
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()

        guard let output = String(data: data, encoding: .utf8),
              let firstField = output.split(whereSeparator: { $0 == "\t" || $0 == " " }).first,
              let kilobytes = Int64(firstField)
        else { return .value(0) }

        return .value(kilobytes * 1024)
    }

    private static func enumeratedSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        for case let child as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]) else { continue }
            if values.isSymbolicLink == true { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// Lists the immediate children of a directory as `Entry`s with their (recursive) sizes computed
    /// concurrently — sizing e.g. 9 top-level folders in parallel instead of one after another is the
    /// difference between opening Home in a couple of seconds versus waiting for the slowest folder
    /// (usually `Library`) to finish before anything else can even start.
    static func immediateChildren(of directory: URL, includeHidden: Bool = false) -> DirectoryListing {
        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        guard let names = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: resourceKeys, options: options) else {
            return DirectoryListing(entries: [], listable: false)
        }

        let candidates: [(url: URL, isDir: Bool, modifiedAt: Date?, fileSize: Int64)] = names.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
            return (url, values.isDirectory ?? false, values.contentModificationDate, Int64(values.fileSize ?? 0))
        }

        let results = ThreadSafeBox<[String: (Int64, SizeStatus)]>([:])
        DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
            let candidate = candidates[index]
            let result: (Int64, SizeStatus) = candidate.isDir ? sizeAndStatus(of: candidate.url) : (candidate.fileSize, .ok)
            results.mutate { $0[candidate.url.path] = result }
        }

        let resolved = results.value
        let entries = candidates.map { candidate -> Entry in
            let (size, status) = resolved[candidate.url.path] ?? (candidate.fileSize, .ok)
            return Entry(url: candidate.url, sizeBytes: size, modifiedAt: candidate.modifiedAt, isDirectory: candidate.isDir, sizeStatus: status)
        }
        return DirectoryListing(entries: entries, listable: true)
    }

    /// Recursively walks a directory tree yielding every file (not directories) it can read,
    /// applying `filter` as it goes so callers can bail out early on huge trees.
    static func walkFiles(root: URL, filter: (Entry) -> Bool, onEntry: (Entry) -> Void) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsPackageDescendants, .skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return }

        for case let url as URL in enumerator {
            if Task.isCancelled { return }
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else { continue }
            if values.isDirectory == true { continue }
            let entry = Entry(url: url, sizeBytes: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate, isDirectory: false, sizeStatus: .ok)
            if filter(entry) {
                onEntry(entry)
            }
        }
    }
}

/// Minimal lock-protected box for collecting results from `DispatchQueue.concurrentPerform`, where
/// multiple threads write to a shared dictionary at once.
final class ThreadSafeBox<Value> {
    private var storage: Value
    private let lock = NSLock()

    init(_ initial: Value) { storage = initial }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}
