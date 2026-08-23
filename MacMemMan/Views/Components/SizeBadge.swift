import SwiftUI

struct SizeBadge: View {
    let bytes: Int64
    var tint: Color = .secondary

    var body: some View {
        Text(bytes.formattedBytes)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Design.brandGradient.opacity(0.15))
                    .frame(width: 84, height: 84)
                Image(systemName: symbolName)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Design.brandGradient)
            }
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
