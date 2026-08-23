import Foundation

/// A file eligible for transparent, lossless compression — deliberately a separate model from
/// `ScanItem` so this feature can never accidentally flow into `SafeDeleteService`. Nothing here
/// is ever deleted; compressed files remain byte-identical when read, just smaller on disk.
struct CompressionCandidate: Identifiable, Hashable, Codable {
    static func == (lhs: CompressionCandidate, rhs: CompressionCandidate) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let path: URL
    let displayName: String
    let sizeBytes: Int64
    let modifiedAt: Date?
    /// Rough, file-type-based guess at how much smaller this will get — real compressors vary by
    /// actual content, so this is only ever labeled as an estimate; the true number is only known
    /// once compression has actually run.
    let estimatedSavingsFraction: Double

    var id: String { path.path }
    var estimatedSavingsBytes: Int64 { Int64(Double(sizeBytes) * estimatedSavingsFraction) }
}
