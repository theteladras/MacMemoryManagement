import SwiftUI

/// A single selectable scan result row, reused across the junk/large-files/duplicates views.
/// Self-contained AI "explain this" support — always visible, and it manages its own key-setup
/// prompt — so every list this row appears in gets the feature for free.
struct ScanItemRow: View {
    let item: ScanItem
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var aiExplanation: String?
    @State private var isLoadingAI = false
    @State private var showingKeySetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)

                IconChip(symbolName: item.category.symbolName, tint: item.category.tint, size: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.displayName)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .lineLimit(1)
                        SafetyBadge(level: item.safety.level)
                    }
                    Text(item.path.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 140, alignment: .trailing)

                Button {
                    if AIAssistService.isAvailable {
                        Task { await explain() }
                    } else {
                        showingKeySetup = true
                    }
                } label: {
                    if isLoadingAI {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isLoadingAI)
                .help("Ask AI what this is")

                SizeBadge(bytes: item.sizeBytes, tint: item.category.tint)
            }

            if let aiExplanation {
                Text(aiExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.leading, 42)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .help(item.safety.reason)
        .sheet(isPresented: $showingKeySetup) {
            AIKeySetupSheet(onSaved: { Task { await explain() } })
        }
    }

    private func explain() async {
        isLoadingAI = true
        defer { isLoadingAI = false }
        do {
            aiExplanation = try await AIAssistService.explain(item: item)
        } catch {
            aiExplanation = error.localizedDescription
        }
    }
}
