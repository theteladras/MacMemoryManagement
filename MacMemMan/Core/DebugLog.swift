import Foundation

/// Plain-file debug logging, same reasoning as `MenuBarController`'s private version: `log
/// show`/`log stream` return zero lines for this process in this dev environment (verified, even
/// for a definitely-logging system process), so temporary diagnosis goes to a plain file instead.
/// Shared here rather than duplicated per-file for anything outside `MenuBarController` that needs
/// it.
enum AppDebugLog {
    static let url = URL(fileURLWithPath: "/tmp/mmm_debug.log")

    static func write(_ message: String) {
        let line = "\(Date()): \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
