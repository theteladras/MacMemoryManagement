import Foundation

/// The only place multi-user cleanup ever deletes anything — mirrors `SafeDeleteService`'s
/// contract (only ever called after the same mandatory Review Sheet) but runs through
/// `AdminShellService` since these paths belong to a different account and this process has no
/// permission to touch them directly. Every path is re-checked against the same known-junk
/// whitelist `MultiUserScanner` used to find it, independent of whatever the manifest claims.
enum AdminDeleteService {
    static func delete(_ items: [ScanItem], mode: DeleteMode) async -> DeleteResult {
        var result = DeleteResult()
        var validItems: [ScanItem] = []

        for item in items {
            if let reason = ProtectedPaths.blockReason(for: item.path) {
                result.failed.append((item, reason))
                continue
            }
            guard isAllowedMultiUserPath(item.path) else {
                result.failed.append((item, "Not a recognized other-user cache/log/trash location — refusing to touch it"))
                continue
            }
            validItems.append(item)
        }
        guard !validItems.isEmpty else { return result }

        var script = "shopt -s nullglob\n"
        for (index, item) in validItems.enumerated() {
            let src = MultiUserScanner.shellQuote(item.path.path)
            switch mode {
            case .trash:
                let comps = item.path.pathComponents
                guard comps.count >= 3 else { continue }
                let trashDir = MultiUserScanner.shellQuote("/\(comps[1])/\(comps[2])/.Trash")
                script += """
                if [ -e \(src) ]; then
                  mkdir -p \(trashDir)
                  dest=\(trashDir)/"$(basename \(src)).$(date +%s)"
                  err=$(mv \(src) "$dest" 2>&1) && echo "OK|IDX\(index)" || echo "FAIL|IDX\(index)|$err"
                else
                  echo "FAIL|IDX\(index)|No longer exists"
                fi

                """
            case .permanent:
                script += """
                if [ -e \(src) ]; then
                  err=$(rm -rf \(src) 2>&1) && echo "OK|IDX\(index)" || echo "FAIL|IDX\(index)|$err"
                else
                  echo "FAIL|IDX\(index)|No longer exists"
                fi

                """
            }
        }

        do {
            let output = try await AdminShellService.run(script: script)
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count >= 2, let index = Int(parts[1].dropFirst(3)), validItems.indices.contains(index) else { continue }
                let item = validItems[index]
                if parts[0] == "OK" {
                    result.successes.append(DeleteResult.Success(item: item, trashedURL: nil))
                    result.freedBytes += item.sizeBytes
                } else {
                    let message = parts.count > 2 ? String(parts[2]) : "Failed"
                    result.failed.append((item, message))
                }
            }
        } catch {
            // The whole privileged batch failed (e.g. the admin prompt was cancelled) — every item
            // that made it past the whitelist check is unresolved, not silently "succeeded".
            for item in validItems {
                result.failed.append((item, error.localizedDescription))
            }
        }

        return result
    }

    /// Defense in depth, independent of `MultiUserScanner`'s own catalog check at scan time: only
    /// `/Users/<name>/Library/Caches`, `/Users/<name>/Library/Logs`, and `/Users/<name>/.Trash`
    /// (and their contents) are ever eligible for privileged deletion — never a bare account home,
    /// never Documents/Desktop/Pictures/anything else, no matter what a manifest claims.
    private static func isAllowedMultiUserPath(_ path: URL) -> Bool {
        let comps = path.pathComponents
        guard comps.count >= 5, comps[0] == "/", comps[1] == "Users" else { return false }
        let relative = comps.dropFirst(3).joined(separator: "/")
        return relative.hasPrefix("Library/Caches/") || relative.hasPrefix("Library/Logs/") || relative.hasPrefix(".Trash/")
    }
}
