import SwiftUI

enum ScanCategory: String, CaseIterable, Identifiable, Codable {
    case userCaches = "App Caches"
    case systemCaches = "System Caches"
    case logs = "Logs"
    case trash = "Trash Bins"
    case browserCaches = "Browser Caches"
    case developerJunk = "Developer Junk"
    case appLeftovers = "App Leftovers"
    case largeFiles = "Large Files"
    case oldFiles = "Old Files"
    case duplicates = "Duplicates"
    case explorerSelection = "Selected in Explorer"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .userCaches: return "internaldrive"
        case .systemCaches: return "gearshape.2"
        case .logs: return "doc.text.magnifyingglass"
        case .trash: return "trash"
        case .browserCaches: return "network"
        case .developerJunk: return "hammer"
        case .appLeftovers: return "app.badge.checkmark"
        case .largeFiles: return "doc.badge.arrow.up"
        case .oldFiles: return "clock.arrow.circlepath"
        case .duplicates: return "doc.on.doc"
        case .explorerSelection: return "list.bullet.indent"
        }
    }

    var tint: Color {
        switch self {
        case .userCaches: return .blue
        case .systemCaches: return .indigo
        case .logs: return .teal
        case .trash: return .gray
        case .browserCaches: return .cyan
        case .developerJunk: return .orange
        case .appLeftovers: return .purple
        case .largeFiles: return .pink
        case .oldFiles: return .brown
        case .duplicates: return .yellow
        case .explorerSelection: return .cyan
        }
    }

    /// Categories that require Full Disk Access to be reliably scanned.
    var requiresFullDiskAccess: Bool {
        switch self {
        case .systemCaches, .logs:
            return true
        default:
            return false
        }
    }
}
