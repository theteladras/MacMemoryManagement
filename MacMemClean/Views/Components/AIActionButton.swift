import SwiftUI

/// A toolbar-level "ask AI to do something" button — always visible (never hidden just because no
/// key is saved yet). Without a key it opens `AIKeySetupSheet` first and re-runs `action`
/// automatically once one is saved, so the user never has to re-discover what they just tapped.
struct AIActionButton: View {
    let title: String
    var symbolName: String = "sparkles"
    let isBusy: Bool
    let action: () async -> Void

    @State private var showingKeySetup = false

    var body: some View {
        Button {
            if AIAssistService.isAvailable {
                Task { await action() }
            } else {
                showingKeySetup = true
            }
        } label: {
            if isBusy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(title)
                }
            } else {
                Label(title, systemImage: symbolName)
            }
        }
        .disabled(isBusy)
        .sheet(isPresented: $showingKeySetup) {
            AIKeySetupSheet(onSaved: { Task { await action() } })
        }
    }
}
