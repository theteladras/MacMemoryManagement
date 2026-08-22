import SwiftUI

/// How comfortable the app is auto-suggesting removal of an item. This is deliberately
/// separate from `ScanCategory` — a category like "Large Files" can contain anything from a
/// disposable ISO download to an irreplaceable family video, and the two need very different
/// defaults and visual treatment.
enum SafetyLevel: Int, Comparable, Codable {
    case safe = 0
    case caution = 1
    case personal = 2

    static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .safe: return "Safe to remove"
        case .caution: return "Use caution"
        case .personal: return "Personal — review"
        }
    }

    var shortLabel: String {
        switch self {
        case .safe: return "Safe"
        case .caution: return "Caution"
        case .personal: return "Personal"
        }
    }

    var symbolName: String {
        switch self {
        case .safe: return "checkmark.seal.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .personal: return "person.crop.circle.badge.exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .safe: return .green
        case .caution: return .yellow
        case .personal: return .red
        }
    }

    /// Whether items at this level should be pre-checked when a scan finishes. Only things the
    /// app is genuinely confident are disposable get auto-selected — anything personal always
    /// requires the user to opt in by hand.
    var autoSelectByDefault: Bool { self == .safe }
}

struct SafetyAssessment {
    let level: SafetyLevel
    let reason: String
}
