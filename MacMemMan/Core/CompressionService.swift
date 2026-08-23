import Foundation

/// Applies transparent APFS/HFS+ compression to files in place, via Apple's own `ditto
/// --hfsCompression` — the same first-party mechanism macOS itself uses for compressed system
/// files, rather than reimplementing the undocumented on-disk decmpfs format ourselves. A
/// compressed file is byte-identical when read back; only its footprint on disk shrinks.
///
/// Safety model: compress to a temp copy, verify it is byte-for-byte identical to the original
/// (`cmp`), and only then atomically replace the original. If anything fails or doesn't verify,
/// the original file is left completely untouched.
enum CompressionService {
    struct Success {
        let candidate: CompressionCandidate
        let beforeBytes: Int64
        let afterBytes: Int64
        var savedBytes: Int64 { max(0, beforeBytes - afterBytes) }
    }

    struct Failure {
        let candidate: CompressionCandidate
        let reason: String
    }

    struct Result {
        var successes: [Success] = []
        var failures: [Failure] = []
        var savedBytes: Int64 { successes.reduce(0) { $0 + $1.savedBytes } }
    }

    private static let processTimeoutSeconds: TimeInterval = 30

    static func compress(_ candidates: [CompressionCandidate], onProgress: @escaping (Int, Int) -> Void = { _, _ in }) async -> Result {
        await Task.detached {
            var result = Result()
            for (index, candidate) in candidates.enumerated() {
                if Task.isCancelled { break }
                switch compressOne(candidate.path) {
                case .success(let before, let after):
                    result.successes.append(Success(candidate: candidate, beforeBytes: before, afterBytes: after))
                case .failure(let reason):
                    result.failures.append(Failure(candidate: candidate, reason: reason))
                }
                onProgress(index + 1, candidates.count)
            }
            return result
        }.value
    }

    private enum Outcome {
        case success(before: Int64, after: Int64)
        case failure(String)
    }

    private static func compressOne(_ url: URL) -> Outcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .failure("No longer exists") }

        let beforeBytes = FileSystemScanner.sizeOf(url)
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".mmclean_compress_\(UUID().uuidString)")

        guard runProcess("/usr/bin/ditto", ["--hfsCompression", url.path, tempURL.path]) else {
            try? fm.removeItem(at: tempURL)
            return .failure("Compression failed or timed out")
        }
        guard fm.fileExists(atPath: tempURL.path) else {
            return .failure("Compression produced no output")
        }

        guard filesAreIdentical(url, tempURL) else {
            try? fm.removeItem(at: tempURL)
            return .failure("Integrity check failed — original left untouched")
        }

        let afterBytes = FileSystemScanner.sizeOf(tempURL)
        guard afterBytes < beforeBytes else {
            try? fm.removeItem(at: tempURL)
            return .failure("No space saved — skipped")
        }

        do {
            _ = try fm.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? fm.removeItem(at: tempURL)
            return .failure("Couldn't replace original: \(error.localizedDescription)")
        }

        return .success(before: beforeBytes, after: FileSystemScanner.sizeOf(url))
    }

    private static func filesAreIdentical(_ a: URL, _ b: URL) -> Bool {
        runProcess("/usr/bin/cmp", ["-s", a.path, b.path])
    }

    /// Runs a process to completion with a hard timeout, returning whether it exited successfully
    /// (status 0). Same "never block forever" discipline as `FileSystemScanner`'s `du` calls.
    private static func runProcess(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        let doneSignal = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in doneSignal.signal() }

        do {
            try process.run()
        } catch {
            return false
        }

        guard doneSignal.wait(timeout: .now() + processTimeoutSeconds) == .success else {
            process.terminationHandler = nil
            process.terminate()
            return false
        }

        return process.terminationStatus == 0
    }
}
