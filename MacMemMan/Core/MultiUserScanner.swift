import Foundation

struct OtherUserAccount: Identifiable, Hashable {
    let username: String
    let fullName: String
    let homeDirectory: URL
    var id: String { username }
}

/// Lets an admin see and clean up cache/log/trash junk sitting in *other* local accounts' home
/// folders — space Activity Monitor/Storage settings can show as "used" but this app otherwise has
/// no way to touch, since a normal process can't even read into another account's home (mode 700).
///
/// Deliberately narrow in scope for safety: every operation here is scoped to the same
/// known-disposable catalog `JunkScanner` already trusts (Caches/Logs/Trash) — never Documents,
/// Desktop, Pictures, or anything else that might hold another person's irreplaceable files. Every
/// read and write goes through `AdminShellService`, so it always costs a real macOS admin-password
/// prompt; nothing here runs silently.
enum MultiUserScanner {
    private struct JunkSpec {
        let relativePath: String
        let label: String
        let listChildren: Bool
    }

    private static let catalog: [JunkSpec] = [
        JunkSpec(relativePath: "Library/Caches", label: "App Caches", listChildren: true),
        JunkSpec(relativePath: "Library/Logs", label: "Logs", listChildren: true),
        JunkSpec(relativePath: ".Trash", label: "Trash", listChildren: true),
    ]

    /// Enumerating account *names* doesn't need admin — `dscl` local directory reads (UniqueID,
    /// RealName, NFSHomeDirectory) are public information, not filesystem content. Only reading
    /// *inside* another account's home (below) needs elevated privileges.
    static func listOtherUsers() -> [OtherUserAccount] {
        guard let listOutput = runDscl(["-list", "/Users", "UniqueID"]) else { return [] }
        let currentUser = NSUserName()

        var accounts: [OtherUserAccount] = []
        for line in listOutput.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let uid = Int(parts.last!) else { continue }
            let username = parts.dropLast().joined(separator: " ")
            // Real user accounts start at 501 on current macOS; anything below is a system/service
            // account with no meaningful "home folder a person put files in".
            guard uid >= 500, username != currentUser else { continue }

            let homePath = runDscl(["-read", "/Users/\(username)", "NFSHomeDirectory"])?
                .replacingOccurrences(of: "NFSHomeDirectory:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/Users/\(username)"
            guard homePath.hasPrefix("/Users/") else { continue } // skip _mbsetupuser-style non-home accounts

            let realName = runDscl(["-read", "/Users/\(username)", "RealName"])?
                .replacingOccurrences(of: "RealName:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            accounts.append(OtherUserAccount(
                username: username,
                fullName: (realName?.isEmpty == false ? realName! : username),
                homeDirectory: URL(fileURLWithPath: homePath)
            ))
        }
        return accounts.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    private static func runDscl(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = ["."] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    /// One admin-authorized shell call sizes every requested account's home folder at once, so
    /// checking several accounts only costs a single password prompt.
    static func homeSizes(for accounts: [OtherUserAccount]) async throws -> [String: Int64] {
        guard !accounts.isEmpty else { return [:] }
        let script = accounts.map { account in
            "printf 'SIZE|\(account.username)|'; du -sk \(shellQuote(account.homeDirectory.path)) 2>/dev/null | cut -f1 || echo 0"
        }.joined(separator: "\n")

        let output = try await AdminShellService.run(script: script)
        var result: [String: Int64] = [:]
        for line in output.split(separator: "\n") where line.hasPrefix("SIZE|") {
            let parts = line.dropFirst(5).split(separator: "|")
            guard parts.count == 2, let kb = Int64(parts[1].trimmingCharacters(in: .whitespaces)) else { continue }
            result[String(parts[0])] = kb * 1024
        }
        return result
    }

    /// Scans exactly the same known-disposable catalog `JunkScanner` uses for the current user,
    /// rooted at `account`'s home instead — one admin prompt covers the whole catalog.
    static func scanJunk(for account: OtherUserAccount) async throws -> [ScanItem] {
        var script = "shopt -s nullglob\n"
        for spec in catalog {
            let root = account.homeDirectory.appendingPathComponent(spec.relativePath).path
            if spec.listChildren {
                script += """
                for f in \(shellQuote(root))/*; do
                  sz=$(du -sk "$f" 2>/dev/null | cut -f1)
                  mt=$(stat -f %m "$f" 2>/dev/null)
                  isdir=$([ -d "$f" ] && echo 1 || echo 0)
                  [ -n "$sz" ] && printf 'REC|%s|%s|%s|%s|%s\\n' "$f" "${sz:-0}" "${mt:-0}" "$isdir" \(shellQuote(spec.label))
                done

                """
            } else {
                script += """
                if [ -e \(shellQuote(root)) ]; then
                  sz=$(du -sk \(shellQuote(root)) 2>/dev/null | cut -f1)
                  mt=$(stat -f %m \(shellQuote(root)) 2>/dev/null)
                  isdir=$([ -d \(shellQuote(root)) ] && echo 1 || echo 0)
                  printf 'REC|%s|%s|%s|%s|%s\\n' \(shellQuote(root)) "${sz:-0}" "${mt:-0}" "$isdir" \(shellQuote(spec.label))
                fi

                """
            }
        }

        let output = try await AdminShellService.run(script: script)
        var items: [ScanItem] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) where line.hasPrefix("REC|") {
            let fields = line.dropFirst(4).components(separatedBy: "|")
            guard fields.count == 5,
                  let kb = Int64(fields[1]), kb > 0,
                  let epoch = TimeInterval(fields[2])
            else { continue }
            let path = URL(fileURLWithPath: fields[0])
            items.append(ScanItem(
                path: path,
                category: .otherUserJunk,
                reason: "\(account.fullName) — \(fields[4])",
                sizeBytes: kb * 1024,
                modifiedAt: epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil,
                isDirectory: fields[3] == "1"
            ))
        }
        return items
    }

    /// Every relative junk root this scanner is allowed to touch, for the extra defense-in-depth
    /// check `AdminDeleteService` runs immediately before deleting anything under `/Users/*`.
    static func isKnownJunkPath(_ path: URL, in account: OtherUserAccount) -> Bool {
        catalog.contains { spec in
            let root = account.homeDirectory.appendingPathComponent(spec.relativePath).path
            return path.path == root || path.path.hasPrefix(root + "/")
        }
    }

    static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
