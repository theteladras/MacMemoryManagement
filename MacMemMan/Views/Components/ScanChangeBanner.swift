import SwiftUI

/// Shown right after a scan completes if there's a previous scan to compare against — "here's
/// what's different" instead of silently swapping the list. Only appears when something actually
/// changed; a no-op rescan stays quiet rather than adding noise every time.
struct ScanChangeBanner: View {
    let change: ScanChangeSummary
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.teal)
                .font(.callout)
            VStack(alignment: .leading, spacing: 2) {
                if change.addedCount > 0 {
                    Text("+\(change.addedCount) new — \(change.addedBytes.formattedBytes)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                }
                if change.removedCount > 0 {
                    Text("-\(change.removedCount) gone — \(change.removedBytes.formattedBytes)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
