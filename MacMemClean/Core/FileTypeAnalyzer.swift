import Foundation

/// Answers "what kind of content is actually using space", scanning across the folders people
/// keep personal content in (Documents, Desktop, Downloads, Pictures, Movies, Music, Public) so
/// a photo doesn't get hidden just because it happens to live in Downloads rather than Pictures.
enum FileTypeAnalyzer {
    struct TypeUsage: Identifiable, Codable {
        let category: FileTypeCategory
        let bytes: Int64
        let count: Int
        var id: String { category.id }
    }

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "bmp", "raw", "cr2", "cr3", "nef", "arw", "dng", "webp", "svg", "psd", "ai", "sketch"]
    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "3gp", "wmv", "flv"]
    private static let audioExtensions: Set<String> = ["mp3", "wav", "aac", "m4a", "flac", "aiff", "alac"]
    private static let documentExtensions: Set<String> = ["pdf", "doc", "docx", "pages", "key", "keynote", "numbers", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "md", "csv"]
    private static let archiveExtensions: Set<String> = ["zip", "dmg", "pkg", "iso", "tar", "gz", "rar", "7z", "bz2"]
    private static let codeExtensions: Set<String> = ["swift", "py", "js", "ts", "tsx", "jsx", "java", "kt", "go", "rs", "c", "cpp", "h", "m", "rb", "php", "html", "css", "json", "yml", "yaml", "sh", "xcodeproj", "xcworkspace"]

    static func defaultRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Public"]
            .map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func category(forExtension ext: String) -> FileTypeCategory {
        let lower = ext.lowercased()
        if imageExtensions.contains(lower) { return .images }
        if videoExtensions.contains(lower) { return .videos }
        if audioExtensions.contains(lower) { return .audio }
        if documentExtensions.contains(lower) { return .documents }
        if archiveExtensions.contains(lower) { return .archives }
        if codeExtensions.contains(lower) { return .code }
        return .other
    }

    static func analyze(roots: [URL] = defaultRoots()) -> [TypeUsage] {
        var totals: [FileTypeCategory: (bytes: Int64, count: Int)] = [:]

        for root in roots {
            if Task.isCancelled { break }
            FileSystemScanner.walkFiles(root: root, filter: { _ in true }) { entry in
                let category = category(forExtension: entry.url.pathExtension)
                var current = totals[category] ?? (0, 0)
                current.bytes += entry.sizeBytes
                current.count += 1
                totals[category] = current
            }
        }

        return FileTypeCategory.allCases.compactMap { category in
            guard let totals = totals[category], totals.bytes > 0 else { return nil }
            return TypeUsage(category: category, bytes: totals.bytes, count: totals.count)
        }.sorted { $0.bytes > $1.bytes }
    }
}
