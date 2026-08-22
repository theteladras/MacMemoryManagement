import Foundation

/// Decides how safe an item is to delete. Two items can carry the exact same `ScanCategory` and
/// warrant totally different treatment — a stale `~/Library/Caches` folder is disposable, but a
/// 4K video sitting in Downloads is not, even though both might show up as a "large file". This
/// only ever escalates caution (category baseline -> path/extension signals -> final level); it
/// never downgrades a category's own baseline, so the assessment stays conservative by construction.
enum SafetyAssessor {
    private static let personalMediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "bmp", "raw", "cr2", "cr3", "nef", "arw", "dng",
        "mov", "mp4", "m4v", "avi", "mkv", "3gp",
        "mp3", "wav", "aac", "m4a", "flac", "aiff",
        "psd", "ai", "sketch", "procreate",
    ]

    private static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "pages", "key", "keynote", "numbers", "xls", "xlsx", "ppt", "pptx",
        "txt", "rtf", "md", "csv",
    ]

    private static let disposableArchiveExtensions: Set<String> = ["dmg", "pkg", "iso"]

    private static let personalFolderNames: Set<String> = [
        "Pictures", "Photos", "Photos Library.photoslibrary", "Movies", "Music", "Desktop", "Documents", "iCloud Drive",
    ]

    private static let disposableFolderNames: Set<String> = [
        "node_modules", ".git", "DerivedData", "dist", "build", "target", ".venv", "venv", ".cache",
        "Caches", "Logs", "CoreSimulator", "Archives",
    ]

    static func assess(_ item: ScanItem) -> SafetyAssessment {
        var level = baseline(for: item.category)
        var reason = baseReason(for: item.category)

        let components = Set(item.path.pathComponents)
        let ext = item.path.pathExtension.lowercased()

        // Disposable, regenerable artifacts pull the level back down toward safe even inside an
        // otherwise personal-looking tree (e.g. `node_modules` sitting under a project in Documents).
        let sitsInDisposableFolder = !components.isDisjoint(with: disposableFolderNames)

        if sitsInDisposableFolder && level != .safe && item.category != .duplicates {
            level = .safe
            reason = "Regenerable build/cache artifact — safe to remove."
        } else if disposableArchiveExtensions.contains(ext) {
            level = max(level, .caution)
            reason = "Installer/disk image — usually safe once you've finished with it, but not automatically re-downloadable."
        } else if personalMediaExtensions.contains(ext) {
            level = .personal
            reason = "Looks like a personal photo, video, or audio file — this may not exist anywhere else."
        } else if documentExtensions.contains(ext) {
            level = max(level, .personal)
            reason = "Looks like a personal or work document — verify it's backed up elsewhere before removing."
        } else if !components.isDisjoint(with: personalFolderNames) && level != .safe {
            level = max(level, .caution)
            if reason.isEmpty || level.rawValue > baseline(for: item.category).rawValue {
                reason = "Located in a personal folder (\(nearestPersonalFolder(item.path) ?? "Home")) — double-check before removing."
            }
        }

        // Anything the app can't positively identify as disposable, sitting under the user's
        // home folder outside caches/logs, defaults to at least caution rather than silently safe.
        if level == .safe && item.category == .duplicates {
            level = .caution
            reason = "Duplicate copy — the other copy will remain, but confirm this isn't the one you meant to keep."
        }

        return SafetyAssessment(level: level, reason: reason)
    }

    private static func baseline(for category: ScanCategory) -> SafetyLevel {
        switch category {
        case .userCaches, .systemCaches, .logs, .trash, .browserCaches, .developerJunk:
            return .safe
        case .appLeftovers:
            return .caution
        case .largeFiles, .oldFiles, .duplicates, .explorerSelection:
            return .caution
        }
    }

    private static func baseReason(for category: ScanCategory) -> String {
        switch category {
        case .userCaches: return "App cache — the app will regenerate it automatically."
        case .systemCaches: return "System cache — macOS regenerates this as needed."
        case .logs: return "Log file — safe to clear, useful only for debugging."
        case .trash: return "Already in the Trash."
        case .browserCaches: return "Browser cache — will be rebuilt automatically; you may be signed out of a few sites."
        case .developerJunk: return "Build artifact — Xcode/Simulator will regenerate it on next build/run."
        case .appLeftovers: return "Leftover from an app you're removing — only needed if you reinstall it."
        case .largeFiles: return "Large file — review before removing."
        case .oldFiles: return "Not opened in a while — review before removing."
        case .duplicates: return "Duplicate file."
        case .explorerSelection: return "Selected from the storage browser — review before removing."
        }
    }

    private static func nearestPersonalFolder(_ url: URL) -> String? {
        url.pathComponents.last(where: personalFolderNames.contains)
    }
}
