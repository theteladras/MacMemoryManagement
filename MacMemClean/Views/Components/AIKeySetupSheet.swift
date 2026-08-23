import SwiftUI

/// Shown whenever any "Ask AI" button is tapped without a saved API key — lets the user paste one
/// in right where they hit the wall, instead of first having to go discover Settings on their own.
struct AIKeySetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    var onSaved: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                IconChip(symbolName: "sparkles", tint: .purple, size: 30, useBrandGradient: true)
                Text("Enable AI Assist")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Spacer()
            }

            Text("AI Assist can explain unfamiliar files, summarize scan results, and suggest what's likely safe to clean up — powered by Claude. It only works with your own Anthropic API key. Only file metadata (name, path, size, dates) is ever sent — never file contents.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                Label("Get an API key at console.anthropic.com", systemImage: "arrow.up.forward.app")
            }
            .font(.callout)

            VStack(alignment: .leading, spacing: 6) {
                Text("PASTE YOUR KEY")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                SecureField("sk-ant-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Stored in the macOS Keychain only.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save & Continue") {
                    KeychainService.saveAPIKey(apiKey)
                    dismiss()
                    onSaved()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.gradient)
                .disabled(apiKey.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
