import SwiftUI

/// Compact pill shown on every scan result row and in the Review Sheet — the "is this safe to
/// delete" signal from `SafetyAssessor`, always visible, never buried behind a tap.
struct SafetyBadge: View {
    let level: SafetyLevel
    var showLabel: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.symbolName)
            if showLabel {
                Text(level.shortLabel)
            }
        }
        .font(.system(.caption2, design: .rounded).weight(.bold))
        .foregroundStyle(level.tint == .yellow ? Color(red: 0.55, green: 0.42, blue: 0) : level.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(level.tint.opacity(0.16), in: Capsule())
    }
}

/// Longer-form explanation used in the Review Sheet and detail rows where there's room to say why.
struct SafetyReasonLabel: View {
    let assessment: SafetyAssessment

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: assessment.level.symbolName)
                .foregroundStyle(assessment.level.tint)
                .font(.caption)
            Text(assessment.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
