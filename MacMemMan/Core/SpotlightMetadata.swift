import Foundation

/// Thin wrapper around `/usr/bin/mdls` for reading Spotlight metadata — used to answer "when was
/// this app last opened", which isn't available from `FileManager` at all (creation/modification
/// dates don't track launches; Spotlight's `kMDItemLastUsedDate` does).
enum SpotlightMetadata {
    private static let timeoutSeconds: TimeInterval = 3

    static func lastUsedDate(for url: URL) -> Date? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = ["-raw", "-name", "kMDItemLastUsedDate", url.path]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        let doneSignal = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in doneSignal.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        guard doneSignal.wait(timeout: .now() + timeoutSeconds) == .success else {
            process.terminationHandler = nil
            process.terminate()
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              output != "(null)", !output.isEmpty
        else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: output)
    }
}
