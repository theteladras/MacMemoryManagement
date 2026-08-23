import SwiftUI

struct JunkScanView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var viewModel = JunkScanViewModel.shared
    @State private var aiSummary: String?
    @State private var isSummarizing = false
    @State private var isSuggesting = false
    @State private var suggestionNote: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Caches & Junk").font(.system(.title3, design: .rounded).weight(.bold))
                InfoButton(text: "Scans known-safe cache, log, browser-cache, developer-tool, and Trash locations. Only items rated \"Safe\" are pre-checked — system-wide locations are skipped without Full Disk Access. Nothing is removed until you review and confirm.")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            toolbar

            if let change = viewModel.lastChange {
                ScanChangeBanner(change: change) { viewModel.lastChange = nil }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            if let aiSummary {
                AISummaryBanner(text: aiSummary) { self.aiSummary = nil }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            if let suggestionNote {
                AISummaryBanner(text: suggestionNote, symbolName: "checkmark.circle") { self.suggestionNote = nil }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            Group {
                // Cached/previous results (if any) take priority over the scanning spinner, so a
                // background refresh updates the list in place instead of blanking the screen —
                // the spinner only owns the screen for a genuine first-ever scan.
                if viewModel.hasScanned && !viewModel.items.isEmpty {
                    list
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if viewModel.isScanning {
                    ProgressView(viewModel.statusText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if !viewModel.hasScanned {
                    EmptyStateView(
                        symbolName: "trash.circle",
                        title: "Caches, Logs & System Junk",
                        message: "Scans known-safe cache, log, browser, developer and trash locations. Nothing is removed until you review and confirm.",
                        actionTitle: "Scan",
                        action: { Task { await viewModel.scan() } }
                    )
                    .transition(.opacity)
                } else {
                    EmptyStateView(symbolName: "checkmark.circle", title: "All Clean", message: "No junk found in known locations.")
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.isScanning)
            .animation(.easeInOut(duration: 0.25), value: viewModel.hasScanned)
        }
        .navigationTitle("Caches & Junk")
    }

    private var toolbar: some View {
        HStack {
            if viewModel.hasScanned {
                Text("\(viewModel.items.count) items found")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                if viewModel.isScanning {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Select All") { viewModel.selectAll() }
                Button("Select None") { viewModel.selectNone() }
                AIActionButton(title: "Summarize", isBusy: isSummarizing) { await summarize() }
                AIActionButton(title: "AI Suggest", isBusy: isSuggesting) { await suggestSelection() }
                Button {
                    Task { await viewModel.scan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isScanning)
            } else {
                Spacer()
            }
        }
        .padding()
    }

    private func summarize() async {
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            aiSummary = try await AIAssistService.summarize(items: viewModel.items, context: "Caches & Junk")
        } catch {
            aiSummary = error.localizedDescription
        }
    }

    private func suggestSelection() async {
        isSuggesting = true
        defer { isSuggesting = false }
        do {
            let suggestions = try await AIAssistService.suggestSelection(items: viewModel.items)
            for item in viewModel.items where suggestions[item.id] != nil {
                if !viewModel.selectedIDs.contains(item.id) { viewModel.toggle(item) }
            }
            suggestionNote = suggestions.isEmpty
                ? "AI didn't find any additional items it was confident about."
                : "AI selected \(suggestions.count) item(s): " + suggestions.values.prefix(4).joined(separator: "; ") + (suggestions.count > 4 ? "…" : "")
        } catch {
            suggestionNote = error.localizedDescription
        }
    }

    private var groupedItems: [(category: ScanCategory, items: [ScanItem])] {
        let grouped = Dictionary(grouping: viewModel.items, by: \.category)
        return ScanCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List {
                ForEach(groupedItems, id: \.category) { group in
                    Section {
                        ForEach(group.items) { item in
                            ScanItemRow(item: item, isSelected: viewModel.selectedIDs.contains(item.id)) {
                                viewModel.toggle(item)
                            }
                        }
                    } header: {
                        SectionHeaderBar(
                            title: group.category.rawValue,
                            symbolName: group.category.symbolName,
                            tint: group.category.tint,
                            items: group.items,
                            note: (group.category.requiresFullDiskAccess && !appState.permissions.hasFullDiskAccess) ? "Needs Full Disk Access" : nil
                        )
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(viewModel.selectedItems.count) selected")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                    Text(viewModel.selectedBytes.formattedBytes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review & Clean…") {
                    appState.requestReview(ReviewManifest(title: "Clean Junk & Caches", items: viewModel.selectedItems, onDeleted: { viewModel.removeFromResults($0) }))
                }
                .buttonStyle(.gradient)
                .controlSize(.large)
                .disabled(viewModel.selectedItems.isEmpty)
            }
            .padding()
        }
    }
}
