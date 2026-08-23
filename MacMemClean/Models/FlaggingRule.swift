import SwiftUI

/// A user-defined override for how the safety assessor treats matching items — lets someone
/// extend or correct the built-in heuristics with knowledge only they have (e.g. "everything
/// under ~/Archive/OldProjects is fine to wipe" or "never touch anything named *contract*").
struct FlaggingRule: Identifiable, Codable, Equatable {
    enum MatchType: String, Codable, CaseIterable, Identifiable {
        case namePattern
        case fileExtension
        case path

        var id: String { rawValue }

        var label: String {
            switch self {
            case .namePattern: return "Name Pattern"
            case .fileExtension: return "File Type"
            case .path: return "Specific Path"
            }
        }

        var placeholder: String {
            switch self {
            case .namePattern: return "e.g. *invoice* or backup-*.zip"
            case .fileExtension: return "e.g. tmp or psd"
            case .path: return "e.g. ~/Downloads/OldProjects"
            }
        }

        var helpText: String {
            switch self {
            case .namePattern: return "Matches the file/folder name — use * as a wildcard."
            case .fileExtension: return "Matches by extension, regardless of name or location."
            case .path: return "Matches this exact file/folder, or anything inside it."
            }
        }
    }

    enum Treatment: String, Codable, CaseIterable, Identifiable {
        case flagAsJunk
        case neverDelete

        var id: String { rawValue }

        var label: String {
            switch self {
            case .flagAsJunk: return "Treat as Junk"
            case .neverDelete: return "Never Delete"
            }
        }

        var symbolName: String {
            switch self {
            case .flagAsJunk: return "trash.circle.fill"
            case .neverDelete: return "lock.shield.fill"
            }
        }

        var tint: Color {
            switch self {
            case .flagAsJunk: return .green
            case .neverDelete: return .red
            }
        }
    }

    let id: UUID
    var matchType: MatchType
    var pattern: String
    var treatment: Treatment
    var isEnabled: Bool

    init(id: UUID = UUID(), matchType: MatchType, pattern: String, treatment: Treatment, isEnabled: Bool = true) {
        self.id = id
        self.matchType = matchType
        self.pattern = pattern
        self.treatment = treatment
        self.isEnabled = isEnabled
    }
}
