import AppKit
import SwiftUI

/// A permanent, on-disk audit trail of everything MacMemMan has actually deleted — separate
/// from any single scan's results, so "what did this app remove last week" always has an answer.
struct DeletionHistoryView: View {
    @ObservedObject private var store = DeletionHistoryStore.shared
    @State private var confirmingClear = false

    private var groupedByDay: [(day: Date, entries: [DeletionLogEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in (day, grouped[day]!.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryCard

            if store.entries.isEmpty {
                EmptyStateView(
                    symbolName: "clock.arrow.circlepath",
                    title: "No History Yet",
                    message: "Every deletion you confirm in the Review screen will show up here, with what was removed and when."
                )
            } else {
                list
            }
        }
        .navigationTitle("History")
        .animation(.easeInOut(duration: 0.25), value: store.entries.count)
    }

    private var summaryCard: some View {
        HStack(spacing: 14) {
            IconChip(symbolName: "clock.arrow.circlepath", tint: .green, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Deletion History")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    InfoButton(text: "Every deletion you confirm in the Review screen is logged here permanently, including anything that failed and why — separate from any single scan's on-screen results, and stored locally even after you quit the app.")
                }
                Text(store.entries.isEmpty ? "Nothing recorded yet" : "\(store.entries.count) entries · \(store.totalFreedBytes.formattedBytes) freed in total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !store.entries.isEmpty {
                Button("Clear History", role: .destructive) { confirmingClear = true }
                    .confirmationDialog("Clear all deletion history?", isPresented: $confirmingClear, titleVisibility: .visible) {
                        Button("Clear History", role: .destructive) { store.clear() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This only clears the log — it does not restore or re-delete any files.")
                    }
            }
        }
        .cardStyle(padding: 16)
        .padding([.horizontal, .top])
        .padding(.bottom, 8)
    }

    private var list: some View {
        List {
            ForEach(groupedByDay, id: \.day) { group in
                Section {
                    ForEach(group.entries) { entry in
                        HistoryRow(entry: entry)
                    }
                } header: {
                    Text(sectionTitle(for: group.day))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func sectionTitle(for day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: day)
    }
}

private struct HistoryRow: View {
    let entry: DeletionLogEntry

    private var failureReason: String? {
        if case .failed(let reason) = entry.outcome { return reason }
        return nil
    }

    private var canReveal: Bool {
        guard entry.mode == .trash, let trashedPath = entry.trashedPath, failureReason == nil else { return false }
        return FileManager.default.fileExists(atPath: trashedPath)
    }

    var body: some View {
        HStack(spacing: 10) {
            IconChip(symbolName: entry.category.symbolName, tint: entry.category.tint, size: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.system(.callout, design: .rounded))
                        .lineLimit(1)
                    modeBadge
                    if failureReason != nil {
                        Label("Failed", systemImage: "exclamationmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                    }
                }
                Text(failureReason ?? entry.path)
                    .font(.caption)
                    .foregroundStyle(failureReason != nil ? .red : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(entry.date, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)

            if canReveal {
                Button {
                    NSWorkspace.shared.selectFile(entry.trashedPath, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Trash")
            }

            SizeBadge(bytes: entry.sizeBytes, tint: entry.category.tint)
        }
        .padding(.vertical, 3)
        .opacity(failureReason != nil ? 0.7 : 1)
    }

    private var modeBadge: some View {
        Image(systemName: entry.mode == .trash ? "trash" : "trash.slash")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .help(entry.mode == .trash ? "Moved to Trash" : "Deleted permanently")
    }
}
