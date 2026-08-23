import SwiftUI

/// A single horizontal capacity bar split into proportional colored segments — the same pattern
/// macOS's own "About This Mac → Storage" view uses. Answers "how full" and "full of what" in one
/// glance instead of splitting them into a separate gauge and a separate chart. Segments are
/// individually tappable when `onTapSegment` is provided, to drill into one category.
struct SegmentedCapacityBar: View {
    struct Segment: Identifiable {
        let id: String
        let fraction: Double // 0...1 of the full bar width
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 22
    var onTapSegment: ((String) -> Void)?

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(segment.color.gradient)
                        .frame(width: max(3, geo.size.width * segment.fraction))
                        .contentShape(Rectangle())
                        .onTapGesture { onTapSegment?(segment.id) }
                }
            }
            .animation(.spring(response: 0.7, dampingFraction: 0.85), value: segments.map(\.fraction))
        }
        .frame(height: height)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: height / 3.5, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: height / 3.5, style: .continuous))
    }
}

/// One row in the capacity legend below the bar: colored dot, label, and size. Tappable when
/// `onTap` is provided — the legend text is a much easier target to hit than a thin bar segment.
struct CapacityLegendRow: View {
    let color: Color
    let label: String
    let bytes: Int64
    var isSelected: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(.caption, design: .rounded).weight(isSelected ? .bold : .regular))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(bytes.formattedBytes)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, onTap != nil ? 4 : 0)
        .background(isSelected ? color.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}
