import SwiftUI

/// A lightweight, hand-drawn donut chart (no Swift Charts sector marks needed) with a thin gap
/// between segments and a spring animation whenever the underlying values change — used for the
/// "By File Type" storage breakdown.
struct DonutChart: View {
    struct Segment: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    var lineWidth: CGFloat = 24

    private var total: Double { max(segments.reduce(0) { $0 + $1.value }, 0.0001) }

    private struct Computed: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let color: Color
    }

    private var computed: [Computed] {
        var cursor: Double = 0
        let gap = segments.count > 1 ? 0.006 : 0.0
        return segments.map { segment in
            let start = cursor / total
            cursor += segment.value
            let end = max(start, cursor / total - gap)
            return Computed(id: segment.id, start: start, end: end, color: segment.color)
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.06), lineWidth: lineWidth)
            ForEach(computed) { segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.spring(response: 0.75, dampingFraction: 0.85), value: segments.map(\.value))
    }
}
