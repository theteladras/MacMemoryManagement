import Foundation

/// Runs a shell script as root via the native macOS admin-password prompt
/// (`osascript … with administrator privileges`) — no custom privileged helper tool/XPC service,
/// which would be real infrastructure for what is, here, an occasional, explicitly user-initiated
/// action (scanning/cleaning another account's cache files). macOS itself caches the authorization
/// for a few minutes, so a "scan" followed by a "clean" right after typically only prompts once.
enum AdminShellService {
    enum AdminShellError: LocalizedError {
        case cancelled
        case timedOut
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Cancelled — no admin password was entered."
            case .timedOut: return "Timed out waiting for the privileged operation to finish."
            case .failed(let message): return message
            }
        }
    }

    /// Generous relative to every other timeout in this app on purpose: unlike a `du`/`ls` call,
    /// this one genuinely needs to wait on a human typing their password, not just disk I/O — but
    /// it still must never hang the app forever, so a real ceiling stays in place.
    private static let timeoutSeconds: TimeInterval = 180

    /// Writes `script` to a private temp file and runs *that* with administrator privileges,
    /// rather than inlining the script text into the AppleScript `do shell script "..."` string —
    /// sidesteps a whole class of quoting/escaping bugs from nesting shell syntax inside AppleScript
    /// string syntax for anything beyond a trivial one-liner.
    static func run(script: String) async throws -> String {
        try await Task.detached {
            let scriptURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("macmemclean-admin-\(UUID().uuidString).sh")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: scriptURL) }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            let appleScript = "do shell script \"/bin/bash \(scriptURL.path)\" with administrator privileges"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let doneSignal = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in doneSignal.signal() }

            do {
                try process.run()
            } catch {
                throw AdminShellError.failed(error.localizedDescription)
            }

            guard doneSignal.wait(timeout: .now() + timeoutSeconds) == .success else {
                process.terminationHandler = nil
                process.terminate()
                throw AdminShellError.timedOut
            }

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus != 0 {
                let errText = String(data: errData, encoding: .utf8) ?? ""
                if errText.contains("User canceled") || errText.contains("-128") {
                    throw AdminShellError.cancelled
                }
                throw AdminShellError.failed(errText.isEmpty ? "Privileged command failed (status \(process.terminationStatus))" : errText)
            }

            return String(data: outData, encoding: .utf8) ?? ""
        }.value
    }
}
