import Foundation

/// Optional AI Assist: helps identify an unfamiliar file/folder before the user decides whether
/// to delete it. Entirely opt-in — only runs when the user has saved an Anthropic API key in
/// Settings. Only metadata is ever sent (path, name, size, dates, extension) — never file contents.
enum AIAssistService {
    enum AIError: LocalizedError {
        case noAPIKey
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No Anthropic API key saved. Add one in Settings to enable AI Assist."
            case .requestFailed(let message): return message
            }
        }
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-haiku-4-5"

    static var isAvailable: Bool {
        KeychainService.loadAPIKey()?.isEmpty == false
    }

    static func explain(item: ScanItem) async throws -> String {
        let sizeText = item.sizeBytes.formattedBytes
        let modifiedText = item.modifiedAt.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "unknown"
        let prompt = """
        A macOS cleanup app found this item on disk. Based only on its name/path/metadata \
        (its contents were NOT sent to you), explain in 2-3 short sentences what it most likely \
        is and whether it's generally safe to delete or move to Trash. If you're not confident, say so.

        Path: \(item.path.path)
        Name: \(item.displayName)
        Category flagged: \(item.category.rawValue)
        Size: \(sizeText)
        Last modified: \(modifiedText)
        Is directory: \(item.isDirectory)
        """
        return try await send(prompt: prompt, maxTokens: 256)
    }

    /// Duplicate-set specific: which copy is most likely the "right"/canonical one to keep, given
    /// where each copy lives and when it was last touched — a judgment the generic "explain a
    /// single item" prompt can't make since it never sees the sibling copies for context.
    static func explainDuplicateGroup(_ group: DuplicateFinder.DuplicateGroup) async throws -> String {
        let listing = group.items.enumerated().map { index, item -> String in
            let modified = item.modifiedAt.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "unknown"
            return "\(index + 1). \(item.path.path) — modified \(modified)"
        }.joined(separator: "\n")

        let prompt = """
        These \(group.items.count) files are byte-for-byte identical copies (\(group.sizeEach.formattedBytes) each), \
        found by a macOS cleanup app. Based only on their paths and modification dates, say in 2-3 short \
        sentences which copy looks like the "right"/original one to keep and why (e.g. which folder looks \
        more intentional, which is oldest/newest), and confirm the others look safe to remove.

        \(listing)
        """
        return try await send(prompt: prompt, maxTokens: 256)
    }

    /// Uninstaller specific: helps decide whether an unfamiliar app is safe to remove, based only
    /// on its name/bundle id and how long it's gone unused — never anything from inside the app.
    static func explainApp(_ app: AppInfo) async throws -> String {
        let prompt = """
        A macOS uninstaller app is showing this application to the user. Based only on its name/bundle \
        identifier and last-used date, explain in 2-3 short sentences what this app most likely is/does \
        and whether it looks safe to uninstall. If you don't recognize it, say so plainly rather than guessing.

        Name: \(app.name)
        Bundle identifier: \(app.bundleIdentifier ?? "unknown")
        \(app.lastUsedLabel)
        Size: \(app.sizeBytes.formattedBytes)
        """
        return try await send(prompt: prompt, maxTokens: 256)
    }

    /// Plain-language read on a whole scan result: what's using the most space, what's probably
    /// safe, what deserves a closer look. Capped to the largest 40 items so the prompt (and cost)
    /// stays small regardless of how big the scan was.
    static func summarize(items: [ScanItem], context: String) async throws -> String {
        guard !items.isEmpty else { return "Nothing found to summarize." }
        let top = items.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(40)
        let listing = top.map { "- \($0.displayName) — \($0.sizeBytes.formattedBytes), \($0.category.rawValue), \($0.safety.level.shortLabel)" }.joined(separator: "\n")
        let totalBytes = items.reduce(Int64(0)) { $0 + $1.sizeBytes }

        let prompt = """
        A macOS cleanup app just ran a "\(context)" scan and found \(items.count) items totaling \(totalBytes.formattedBytes). \
        Here are the largest ones (name, size, category, safety rating):

        \(listing)

        In 3-4 short sentences: summarize what's actually taking up the space, and give a plain-language \
        read on what's probably fine to remove versus what's worth a closer look before deleting. Don't \
        repeat the raw list back.
        """
        return try await send(prompt: prompt, maxTokens: 300)
    }

    /// The Review Sheet's final-check summary — deliberately framed differently from `summarize`
    /// above: that one describes a fresh scan neutrally, this one is a last look at an *already
    /// hand-picked* selection right before deletion, so the prompt explicitly asks the model to
    /// push back if something looks off rather than just describing the list back.
    static func reviewBeforeDeleting(items: [ScanItem]) async throws -> String {
        guard !items.isEmpty else { return "Nothing selected." }
        let totalBytes = items.reduce(Int64(0)) { $0 + $1.sizeBytes }

        let byCategory = Dictionary(grouping: items, by: \.category)
        let categoryLines = ScanCategory.allCases.compactMap { category -> String? in
            guard let group = byCategory[category], !group.isEmpty else { return nil }
            let bytes = group.reduce(Int64(0)) { $0 + $1.sizeBytes }
            return "\(category.rawValue): \(group.count) item(s), \(bytes.formattedBytes)"
        }.joined(separator: "\n")

        let notable = items.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(15)
        let notableLines = notable.map { "- \($0.displayName) — \($0.sizeBytes.formattedBytes), \($0.safety.level.shortLabel): \($0.reason)" }.joined(separator: "\n")
        let personalCount = items.filter { $0.safety.level == .personal }.count

        let prompt = """
        A user is about to remove \(items.count) item(s) totaling \(totalBytes.formattedBytes) via a macOS \
        cleanup app, after selecting them themselves. Breakdown by category:

        \(categoryLines)

        The largest items in the selection:
        \(notableLines)

        \(personalCount) of the selected items are rated "Personal" (photos/videos/documents that may not \
        exist anywhere else).

        In 3-5 short sentences: give a clear, honest picture of what's about to be removed and why that \
        looks reasonable — but be genuinely cautious, not just reassuring. If anything here looks like it \
        could be a mistake (personal-looking files, something unusually large, an inconsistent pattern), \
        say so plainly and specifically instead of glossing over it.
        """
        return try await send(prompt: prompt, maxTokens: 400)
    }

    /// Compress Files specific: unlike `summarize` above (which works off `ScanItem`), compression
    /// candidates are a deliberately separate model — this points out which candidates are the best
    /// first picks (biggest savings, least risk) rather than just repeating the ranked list back.
    static func summarizeCompression(candidates: [CompressionCandidate]) async throws -> String {
        guard !candidates.isEmpty else { return "Nothing found to summarize." }
        let top = candidates.sorted { $0.estimatedSavingsBytes > $1.estimatedSavingsBytes }.prefix(40)
        let listing = top.map { "- \($0.displayName) — \($0.sizeBytes.formattedBytes), ~\($0.estimatedSavingsBytes.formattedBytes) estimated savings" }.joined(separator: "\n")
        let totalBytes = candidates.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let totalSavings = candidates.reduce(Int64(0)) { $0 + $1.estimatedSavingsBytes }

        let prompt = """
        A macOS app just scanned a folder for files that would benefit from lossless APFS compression \
        (files stay byte-identical, just smaller on disk) and found \(candidates.count) candidates \
        totaling \(totalBytes.formattedBytes), with an estimated \(totalSavings.formattedBytes) of \
        potential savings. Here are the largest-savings candidates (name, size, estimated savings):

        \(listing)

        In 2-3 short sentences: point out which of these look like the best first picks for the most \
        space back, and flag anything unusual worth a second look (e.g. an oddly huge log file that \
        might be worth investigating rather than just compressing). Don't repeat the raw list back.
        """
        return try await send(prompt: prompt, maxTokens: 300)
    }

    /// Asks which of the given items are worth suggesting for removal, returning `[item.id: reason]`.
    /// Personal-rated items are filtered out before the request even reaches the model — AI
    /// suggestions never touch anything the app itself won't auto-select.
    static func suggestSelection(items: [ScanItem]) async throws -> [String: String] {
        let candidates = items.filter { $0.safety.level != .personal }.prefix(60)
        guard !candidates.isEmpty else { return [:] }
        let listing = candidates.map { "\($0.id)|\($0.displayName)|\($0.sizeBytes.formattedBytes)|\($0.category.rawValue)|\($0.safety.level.shortLabel)|\($0.reason)" }.joined(separator: "\n")

        let prompt = """
        Below are candidate files/folders a macOS cleanup app found (anything rated "Personal" has \
        already been excluded — never suggest those). Each line is: id|name|size|category|safety|reason.

        \(listing)

        Reply with ONLY a JSON object mapping id to a short reason (under 12 words) for the ones you'd \
        suggest removing. Skip anything you're not fairly confident about. If none seem worth suggesting, \
        reply with {}. No markdown, no explanation outside the JSON.
        """
        let raw = try await send(prompt: prompt, maxTokens: 1024)
        return parseSuggestionJSON(raw, validIDs: Set(candidates.map(\.id)))
    }

    private static func parseSuggestionJSON(_ text: String, validIDs: Set<String>) -> [String: String] {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return object.filter { validIDs.contains($0.key) }
    }

    private static func send(prompt: String, maxTokens: Int) async throws -> String {
        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            throw AIError.noAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": "You are a concise macOS storage-cleanup assistant.",
            "messages": [["role": "user", "content": prompt]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.requestFailed("No response from server")
        }
        guard httpResponse.statusCode == 200 else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw AIError.requestFailed(message ?? "Request failed with status \(httpResponse.statusCode)")
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else {
            throw AIError.requestFailed("Unexpected response format")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
