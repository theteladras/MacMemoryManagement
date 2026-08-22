import Foundation

/// How much ground an automatic background scan covers. Every level still only *finds* things —
/// nothing is ever deleted without the user approving it in the Review screen, same as a manual
/// scan. This only controls what gets included in that proposal.
enum CleanupAggressiveness: String, Codable, CaseIterable, Identifiable {
    case light
    case balanced
    case aggressive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .balanced: return "Balanced"
        case .aggressive: return "Aggressive"
        }
    }

    var description: String {
        switch self {
        case .light: return "Only known-safe caches, logs & junk."
        case .balanced: return "Adds large/old files in Downloads (100MB+, 180+ days)."
        case .aggressive: return "Adds duplicate files, and lowers thresholds to 50MB / 90 days."
        }
    }
}
