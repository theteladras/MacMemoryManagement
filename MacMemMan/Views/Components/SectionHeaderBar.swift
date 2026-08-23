import SwiftUI

/// Reusable list-section header: icon, title, item count, total size, and a compact
/// safe/caution/personal composition readout — the "granular detail" for what a scan found in
/// one category, at a glance, before the user opens the section.
///
/// Uses `ViewThatFits` to drop to a two-line layout when the sidebar/window is narrow, rather than
/// letting title/note text wrap mid-row and collide with the trailing size/composition readout.
struct SectionHeaderBar: View {
    let title: String
    let symbolName: String
    let tint: Color
    let items: [ScanItem]
    var note: String?

    private var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    private var composition: [SafetyLevel: Int] {
        Dictionary(grouping: items, by: { $0.safety.level }).mapValues(\.count)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                leading
                Spacer(minLength: 12)
                trailing
            }
            VStack(alignment: .leading, spacing: 4) {
                leading
                HStack {
                    Spacer()
                    trailing
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var leading: some View {
        HStack(spacing: 8) {
            IconChip(symbolName: symbolName, tint: tint, size: 22)
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .layoutPriority(1)
            Text("\(items.count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15), in: Capsule())
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }

    private var trailing: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach([SafetyLevel.safe, .caution, .personal], id: \.self) { level in
                    if let count = composition[level], count > 0 {
                        HStack(spacing: 3) {
                            Circle().fill(level.tint).frame(width: 6, height: 6)
                            Text("\(count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text(totalBytes.formattedBytes)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .fixedSize()
        }
    }
}
