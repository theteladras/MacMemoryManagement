import SwiftUI

/// Classifies files by what they actually are, independent of which folder they happen to sit
/// in — a `.heic` in Downloads counts as a Photo just as much as one in Pictures. Used by the
/// Overview "By File Type" breakdown so media isn't hidden inside a generic "Downloads" bucket.
enum FileTypeCategory: String, CaseIterable, Identifiable, Codable {
    case images = "Images"
    case videos = "Videos"
    case audio = "Audio"
    case documents = "Documents"
    case archives = "Archives & Installers"
    case code = "Code & Dev"
    case other = "Other"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .images: return "photo.fill"
        case .videos: return "film.fill"
        case .audio: return "waveform"
        case .documents: return "doc.text.fill"
        case .archives: return "archivebox.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "questionmark.folder.fill"
        }
    }

    var tint: Color {
        switch self {
        case .images: return .blue
        case .videos: return .purple
        case .audio: return .pink
        case .documents: return .indigo
        case .archives: return .orange
        case .code: return .teal
        case .other: return .gray
        }
    }
}
