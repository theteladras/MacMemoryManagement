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
        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            throw AIError.noAPIKey
        }

        let sizeText = item.sizeBytes.formattedBytes
        let modifiedText = item.modifiedAt.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "unknown"
        let userPrompt = """
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

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "system": "You are a concise macOS storage-cleanup assistant. Keep answers to 2-3 sentences.",
            "messages": [["role": "user", "content": userPrompt]],
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
