import SwiftUI

struct DiskUsageSummary {
    var totalBytes: Int64 = 0
    var freeBytes: Int64 = 0
    var breakdown: [DiskCategoryUsage] = []

    var usedBytes: Int64 { max(0, totalBytes - freeBytes) }
    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    /// Used space the top-level breakdown doesn't account for (hidden system files, swap, other
    /// users' data, etc.) — shown as its own neutral "Other" segment so the capacity bar always
    /// adds up to the real used/free split instead of silently under-representing usage.
    var otherBytes: Int64 {
        max(0, usedBytes - breakdown.reduce(0) { $0 + $1.bytes })
    }
}

struct DiskCategoryUsage: Identifiable {
    let id = UUID()
    let name: String
    let symbolName: String
    let bytes: Int64
    let tint: Color

    init(name: String, symbolName: String, bytes: Int64, tint: Color) {
        self.name = name
        self.symbolName = symbolName
        self.bytes = bytes
        self.tint = tint
    }

    /// `Color` isn't `Codable`, so a cached breakdown is restored by name and the tint re-derived
    /// here — the same fixed name→color mapping `DiskUsageAnalyzer.topLevelBreakdown()` already uses.
    init(cached: CachedCategoryUsage) {
        self.init(name: cached.name, symbolName: cached.symbolName, bytes: cached.bytes, tint: Self.tint(forName: cached.name))
    }

    static func tint(forName name: String) -> Color {
        switch name {
        case "Applications": return .purple
        case "Documents & Desktop": return .indigo
        case "Downloads": return .teal
        case "Photos, Movies & Music": return .pink
        case "System & Library": return .orange
        default: return .gray
        }
    }
}

/// A `Codable` stand-in for `DiskCategoryUsage` used only for disk caching — see that type's
/// `init(cached:)` for how the tint comes back on load.
struct CachedCategoryUsage: Codable {
    let name: String
    let symbolName: String
    let bytes: Int64
}

extension DiskCategoryUsage {
    var cached: CachedCategoryUsage { CachedCategoryUsage(name: name, symbolName: symbolName, bytes: bytes) }
}

/// A `Codable` stand-in for `DiskUsageSummary`, persisted so Overview can show the last known
/// numbers immediately on relaunch while a fresh `loadSummary()` runs in the background.
struct CachedDiskUsageSummary: Codable {
    let totalBytes: Int64
    let freeBytes: Int64
    let breakdown: [CachedCategoryUsage]
}

extension DiskUsageSummary {
    var cached: CachedDiskUsageSummary {
        CachedDiskUsageSummary(totalBytes: totalBytes, freeBytes: freeBytes, breakdown: breakdown.map(\.cached))
    }

    init(cached: CachedDiskUsageSummary) {
        self.init(totalBytes: cached.totalBytes, freeBytes: cached.freeBytes, breakdown: cached.breakdown.map(DiskCategoryUsage.init(cached:)))
    }
}
