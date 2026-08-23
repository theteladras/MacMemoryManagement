import AppKit
import Foundation

struct AppInfo: Identifiable, Hashable {
    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: String // bundle path, stable per app
    let bundlePath: URL
    let bundleIdentifier: String?
    let name: String
    let version: String?
    let sizeBytes: Int64
    let icon: NSImage?
    let lastUsedDate: Date?

    var lastUsedLabel: String {
        guard let lastUsedDate else { return "Last used: unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last used " + formatter.localizedString(for: lastUsedDate, relativeTo: Date())
    }

    /// Hasn't been opened in 6+ months — a signal (not a verdict) that this might be worth
    /// reconsidering, surfaced the same way stale files are elsewhere in the app.
    var isStale: Bool {
        guard let lastUsedDate else { return false }
        return Date().timeIntervalSince(lastUsedDate) > 60 * 60 * 24 * 180
    }
}

extension AppInfo: Codable {
    private enum CodingKeys: String, CodingKey {
        case bundlePath, bundleIdentifier, name, version, sizeBytes, lastUsedDate, iconPNG
    }

    /// `NSImage` isn't `Codable` — round-tripped through a PNG instead so the app-list cache can
    /// show real icons immediately on relaunch instead of blank placeholders until `loadApps()`
    /// finishes its own fresh icon lookups.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundlePath = try container.decode(URL.self, forKey: .bundlePath)
        id = bundlePath.path
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        sizeBytes = try container.decode(Int64.self, forKey: .sizeBytes)
        lastUsedDate = try container.decodeIfPresent(Date.self, forKey: .lastUsedDate)
        if let pngData = try container.decodeIfPresent(Data.self, forKey: .iconPNG) {
            icon = NSImage(data: pngData)
        } else {
            icon = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundlePath, forKey: .bundlePath)
        try container.encodeIfPresent(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encodeIfPresent(lastUsedDate, forKey: .lastUsedDate)
        if let icon, let tiff = icon.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try container.encode(png, forKey: .iconPNG)
        }
    }
}

/// Everything found for a single app when the user asks to uninstall it:
/// the app bundle itself plus any leftover support files elsewhere on disk.
struct UninstallPlan {
    let app: AppInfo
    let items: [ScanItem]
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
}
