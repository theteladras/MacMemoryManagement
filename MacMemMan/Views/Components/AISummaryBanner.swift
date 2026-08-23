import SwiftUI

/// A dismissible callout used to surface an AI response (scan summary, selection note) inline in
/// a scan view — the same visual language everywhere AI text shows up outside the Review Sheet.
struct AISummaryBanner: View {
    let text: String
    var symbolName: String = "sparkles"
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(.purple)
                .font(.callout)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
