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
}
