import AppKit
import SwiftUI

/// The add/edit form for a single `FlaggingRule` — a small standalone sheet rather than inline
/// editing in the list, since picking a path benefits from a real `NSOpenPanel` and the match-type
/// switch changes what the pattern field even means (glob vs extension vs path).
struct AddFlaggingRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = FlaggingRulesStore.shared

    @State private var matchType: FlaggingRule.MatchType = .namePattern
    @State private var pattern: String = ""
    @State private var treatment: FlaggingRule.Treatment = .neverDelete

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                IconChip(symbolName: "flag.fill", tint: .yellow, size: 30)
                Text("New Flagging Rule")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("MATCH BY").font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.5)
                Picker("", selection: $matchType) {
                    ForEach(FlaggingRule.MatchType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(matchType.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("PATTERN").font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.5)
                HStack {
                    TextField(matchType.placeholder, text: $pattern)
                        .textFieldStyle(.roundedBorder)
                    if matchType == .path {
                        Button("Choose…") { choosePath() }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TREATMENT").font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.5)
                Picker("", selection: $treatment) {
                    ForEach(FlaggingRule.Treatment.allCases) { option in
                        Label(option.label, systemImage: option.symbolName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(treatment == .neverDelete
                     ? "Matching items are always shown for review but never pre-selected, even if a scan would normally mark them safe."
                     : "Matching items are treated as safe to remove — they'll be pre-selected in scans, even outside the usual cache/log locations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Rule") {
                    store.add(FlaggingRule(matchType: matchType, pattern: pattern.trimmingCharacters(in: .whitespacesAndNewlines), treatment: treatment))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.gradient)
                .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            pattern = url.path
        }
    }
}
