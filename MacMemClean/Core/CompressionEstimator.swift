import Foundation

/// Rough per-extension compression ratio estimates, used only to give the user a "you'll probably
/// save around X" figure before running anything. Real gains depend on actual content — text-like
/// and uncompressed formats compress well, anything already compressed (images/video/archives)
/// barely shrinks at all, so those are excluded entirely rather than shown with a misleading ~0%.
enum CompressionEstimator {
    private static let estimatedSavingsFraction: [String: Double] = [
        // Text / logs / structured data — compress very well.
        "log": 0.75, "txt": 0.6, "csv": 0.65, "json": 0.7, "xml": 0.7, "plist": 0.5,
        "sql": 0.7, "md": 0.6, "yml": 0.65, "yaml": 0.65,
        // Databases — moderate, depends heavily on contents.
        "db": 0.4, "sqlite": 0.4, "sqlite3": 0.4,
        // Uncompressed audio/image formats — moderate to good.
        "wav": 0.45, "aiff": 0.45, "aif": 0.45,
        "bmp": 0.7, "tiff": 0.5, "tif": 0.5, "psd": 0.35,
        // Source code — compresses well, it's just text.
        "c": 0.65, "cpp": 0.65, "h": 0.65, "hpp": 0.65, "swift": 0.65, "py": 0.65,
        "js": 0.6, "ts": 0.6, "java": 0.6, "html": 0.65, "css": 0.6,
    ]

    /// Returns nil for anything not worth attempting — already-compressed formats (jpg, mp4, zip,
    /// most modern media) where transparent compression would spend CPU for near-zero gain.
    static func estimatedSavingsFraction(forExtension ext: String) -> Double? {
        estimatedSavingsFraction[ext.lowercased()]
    }
}
