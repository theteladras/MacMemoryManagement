import AppKit
import SwiftUI

struct LargeOldFilesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var viewModel = LargeOldFilesViewModel.shared
    @State private var aiSummary: String?
    @State private var isSummarizing = false
    @State private var isSuggesting = false
    @State private var suggestionNote: String?

    var body: some View {
        VStack(spacing: 0) {
            controls

            if let change = viewModel.lastChange {
                ScanChangeBanner(change: change) { viewModel.lastChange = nil }
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            if let aiSummary {
                AISummaryBanner(text: aiSummary) { self.aiSummary = nil }
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            if let suggestionNote {
                AISummaryBanner(text: suggestionNote, symbolName: "checkmark.circle") { self.suggestionNote = nil }
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            Group {
                // Cached/previous results take priority over the scanning spinner — see
                // `JunkScanView` for the same pattern and why.
                if viewModel.isScanning && !viewModel.hasScanned {
                    ProgressView("Scanning \(viewModel.scanRoot.lastPathComponent)…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if !viewModel.hasScanned {
                    EmptyStateView(
                        symbolName: "doc.badge.clock",
                        title: "Large & Old Files",
                        message: "Finds files over \(Int(viewModel.minSizeMB)) MB or untouched for \(viewModel.minAgeDays)+ days in the selected folder.",
                        actionTitle: "Scan",
                        action: { Task { await viewModel.scan() } }
                    )
                    .transition(.opacity)
                } else if viewModel.allItems.isEmpty {
                    EmptyStateView(symbolName: "checkmark.circle", title: "Nothing Found", message: "No large or stale files matched your thresholds.")
                        .transition(.opacity)
                } else if viewModel.filteredLargeItems.isEmpty && viewModel.filteredOldItems.isEmpty {
                    EmptyStateView(symbolName: "line.3.horizontal.decrease.circle", title: "No Matches", message: "Nothing matches the current filters.", actionTitle: "Clear Filters") {
                        viewModel.safetyFilter = nil
                        viewModel.typeFilter = nil
                    }
                    .transition(.opacity)
                } else {
                    list
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.isScanning)
            .animation(.easeInOut(duration: 0.25), value: viewModel.hasScanned)
        }
        .navigationTitle("Large & Old Files")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("Large & Old Files").font(.system(.title3, design: .rounded).weight(.bold))
                InfoButton(text: "Finds files at or above the size threshold, or untouched since before the age threshold, inside the chosen folder. Nothing is pre-selected — these are your own files, so you always pick what to remove by hand.")
            }
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(.pink)
                Text(viewModel.scanRoot.path)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose…") { chooseFolder() }
                Spacer()
                if viewModel.hasScanned && !viewModel.allItems.isEmpty {
                    AIActionButton(title: "Summarize", isBusy: isSummarizing) { await summarize() }
                    AIActionButton(title: "AI Suggest", isBusy: isSuggesting) { await suggestSelection() }
                }
                Button {
                    Task { await viewModel.scan() }
                } label: {
                    Label(viewModel.isScanning ? "Scanning…" : "Scan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.gradient)
                .disabled(viewModel.isScanning)
            }

            HStack(spacing: 24) {
                HStack {
                    Text("Min size").foregroundStyle(.secondary)
                    Slider(value: $viewModel.minSizeMB, in: 10...2000, step: 10)
                        .frame(width: 160)
                    Text("\(Int(viewModel.minSizeMB)) MB")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .frame(width: 60, alignment: .leading)
                }
                HStack {
                    Text("Older than").foregroundStyle(.secondary)
                    Stepper("\(viewModel.minAgeDays) days", value: $viewModel.minAgeDays, in: 30...730, step: 30)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                }
            }
            .font(.callout)

            if viewModel.hasScanned && !viewModel.allItems.isEmpty {
                filterBar
            }
        }
        .cardStyle(padding: 16)
        .padding([.horizontal, .top])
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)

            Menu {
                Button("All Safety Levels") { viewModel.safetyFilter = nil }
                Divider()
                ForEach([SafetyLevel.safe, .caution, .personal], id: \.self) { level in
                    Button {
                        viewModel.safetyFilter = level
                    } label: {
                        Label(level.shortLabel, systemImage: level.symbolName)
                    }
                }
            } label: {
                Label(viewModel.safetyFilter?.shortLabel ?? "Safety: All", systemImage: viewModel.safetyFilter?.symbolName ?? "shield")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Button("All File Types") { viewModel.typeFilter = nil }
                Divider()
                ForEach(viewModel.availableTypeFilters) { category in
                    Button {
                        viewModel.typeFilter = category
                    } label: {
                        Label(category.rawValue, systemImage: category.symbolName)
                    }
                }
            } label: {
                Label(viewModel.typeFilter?.rawValue ?? "Type: All", systemImage: viewModel.typeFilter?.symbolName ?? "doc")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if viewModel.hasActiveFilters {
                Button("Clear") {
                    viewModel.safetyFilter = nil
                    viewModel.typeFilter = nil
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Spacer()
        }
        .font(.callout)
    }

    private var list: some View {
        VStack(spacing: 0) {
            List {
                if !viewModel.filteredLargeItems.isEmpty {
                    Section {
                        ForEach(viewModel.filteredLargeItems) { item in
                            ScanItemRow(item: item, isSelected: viewModel.selectedIDs.contains(item.id)) {
                                viewModel.toggle(item)
                            }
                        }
                    } header: {
                        SectionHeaderBar(title: "Large Files", symbolName: "doc.badge.arrow.up", tint: .pink, items: viewModel.filteredLargeItems)
                    }
                }
                if !viewModel.filteredOldItems.isEmpty {
                    Section {
                        ForEach(viewModel.filteredOldItems) { item in
                            ScanItemRow(item: item, isSelected: viewModel.selectedIDs.contains(item.id)) {
                                viewModel.toggle(item)
                            }
                        }
                    } header: {
                        SectionHeaderBar(title: "Old Files", symbolName: "clock.arrow.circlepath", tint: .brown, items: viewModel.filteredOldItems)
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
                    appState.requestReview(ReviewManifest(title: "Clean Large & Old Files", items: viewModel.selectedItems, onDeleted: { viewModel.removeFromResults($0) }))
                }
                .buttonStyle(.gradient)
                .controlSize(.large)
                .disabled(viewModel.selectedItems.isEmpty)
            }
            .padding()
        }
    }

    private func summarize() async {
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            aiSummary = try await AIAssistService.summarize(items: viewModel.allItems, context: "Large & Old Files")
        } catch {
            aiSummary = error.localizedDescription
        }
    }

    private func suggestSelection() async {
        isSuggesting = true
        defer { isSuggesting = false }
        do {
            let suggestions = try await AIAssistService.suggestSelection(items: viewModel.allItems)
            for item in viewModel.allItems where suggestions[item.id] != nil {
                if !viewModel.selectedIDs.contains(item.id) { viewModel.toggle(item) }
            }
            suggestionNote = suggestions.isEmpty
                ? "AI didn't find any additional items it was confident about."
                : "AI selected \(suggestions.count) item(s): " + suggestions.values.prefix(4).joined(separator: "; ") + (suggestions.count > 4 ? "…" : "")
        } catch {
            suggestionNote = error.localizedDescription
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = viewModel.scanRoot
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.scanRoot = url
        }
    }
}
