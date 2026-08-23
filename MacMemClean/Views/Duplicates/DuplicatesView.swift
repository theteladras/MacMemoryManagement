import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var viewModel = DuplicatesViewModel.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var viewMode: ViewMode = .bySet

    /// Folder scan roots are user-configurable (Settings), so this can't be a hardcoded string
    /// anymore — built fresh from whatever's currently set.
    private var scanRootsLabel: String {
        let names = appSettings.duplicateScanRoots.map(\.lastPathComponent)
        switch names.count {
        case 0: return "no folders (add some in Settings)"
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " & " + names[names.count - 1]
        }
    }
    @State private var aiSummary: String?
    @State private var isSummarizing = false
    @State private var isSuggesting = false
    @State private var suggestionNote: String?
    @State private var groupExplanations: [String: String] = [:]
    @State private var loadingGroupID: String?

    private enum ViewMode: String, CaseIterable, Identifiable {
        case bySet = "By Duplicate Set"
        case byFolder = "By Folder"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Duplicates").font(.system(.title3, design: .rounded).weight(.bold))
                InfoButton(text: "Compares files by content (size, then a hash) across \(scanRootsLabel) — edit which folders in Settings. The oldest copy in each set is suggested as the \"KEEP\", but personal photos, videos & documents are never pre-selected — only generic duplicates are.")
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
                // Cached/previous results take priority over the scanning spinner — see
                // `JunkScanView` for the same pattern and why.
                if viewModel.isScanning && !viewModel.hasScanned {
                    ProgressView("Comparing files in \(scanRootsLabel)…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if !viewModel.hasScanned {
                    EmptyStateView(
                        symbolName: "doc.on.doc",
                        title: "Duplicate Files",
                        message: "Finds exact duplicate files in \(scanRootsLabel). Personal photos, videos & documents are always left for you to select by hand.",
                        actionTitle: "Scan",
                        action: { Task { await viewModel.scan() } }
                    )
                    .transition(.opacity)
                } else if viewModel.groups.isEmpty {
                    EmptyStateView(symbolName: "checkmark.circle", title: "No Duplicates Found", message: "No exact duplicate files were found.")
                        .transition(.opacity)
                } else if viewMode == .bySet {
                    list
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    folderTree
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.isScanning)
            .animation(.easeInOut(duration: 0.25), value: viewModel.hasScanned)
        }
        .navigationTitle("Duplicates")
    }

    private var toolbar: some View {
        HStack {
            if viewModel.hasScanned && !viewModel.groups.isEmpty {
                Text("\(viewModel.groups.count) duplicate sets")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                Text("·").foregroundStyle(.secondary)
                Text("\(viewModel.wastedBytes.formattedBytes) wasted")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                if viewModel.isScanning {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
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

    private var allItems: [ScanItem] { viewModel.groups.flatMap(\.items) }

    private func summarize() async {
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            aiSummary = try await AIAssistService.summarize(items: allItems, context: "Duplicate Files")
        } catch {
            aiSummary = error.localizedDescription
        }
    }

    private func suggestSelection() async {
        isSuggesting = true
        defer { isSuggesting = false }
        do {
            let suggestions = try await AIAssistService.suggestSelection(items: allItems)
            for item in allItems where suggestions[item.id] != nil {
                if !viewModel.selectedIDs.contains(item.id) { viewModel.toggle(item) }
            }
            suggestionNote = suggestions.isEmpty
                ? "AI didn't find any additional copies it was confident about."
                : "AI selected \(suggestions.count) item(s): " + suggestions.values.prefix(4).joined(separator: "; ") + (suggestions.count > 4 ? "…" : "")
        } catch {
            suggestionNote = error.localizedDescription
        }
    }

    private func explainGroup(_ group: DuplicateFinder.DuplicateGroup) async {
        loadingGroupID = group.id
        defer { loadingGroupID = nil }
        do {
            groupExplanations[group.id] = try await AIAssistService.explainDuplicateGroup(group)
        } catch {
            groupExplanations[group.id] = error.localizedDescription
        }
    }

    @ViewBuilder
    private func treeRow(_ node: DuplicateTreeNode) -> some View {
        if node.isFolder {
            treeFolderRow(node)
        } else if let item = node.item {
            treeLeafRow(node, item)
        }
    }

    private func treeFolderRow(_ node: DuplicateTreeNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill").foregroundStyle(.yellow)
            Text(node.name).font(.system(.callout, design: .rounded).weight(.semibold))
            Spacer()
            Text(node.totalBytes.formattedBytes)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func treeLeafRow(_ node: DuplicateTreeNode, _ item: ScanItem) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { viewModel.selectedIDs.contains(item.id) },
                set: { _ in viewModel.toggle(item) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Text(node.isKeeper ? "KEEP" : "")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
                .frame(width: 40, alignment: .leading)

            IconChip(symbolName: "doc.fill", tint: .yellow, size: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName).font(.system(.callout, design: .rounded)).lineLimit(1)
                    SafetyBadge(level: item.safety.level)
                }
                Text("\(node.copiesInGroup) copies in this set")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
            SizeBadge(bytes: item.sizeBytes, tint: .yellow)
        }
        .opacity(viewModel.selectedIDs.contains(item.id) ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.toggle(item) }
        .help(item.path.path)
    }

    private func locationChip(_ path: URL) -> some View {
        Label(DuplicatesViewModel.locationLabel(for: path), systemImage: "folder")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private var folderTree: some View {
        VStack(spacing: 0) {
            List(viewModel.tree, children: \.children) { node in
                treeRow(node)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            Divider()
            selectionFooter
        }
    }

    private var selectionFooter: some View {
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
                appState.requestReview(ReviewManifest(title: "Clean Duplicate Files", items: viewModel.selectedItems, onDeleted: { items in
                    viewModel.removeItems(withIDs: Set(items.map(\.id)))
                }))
            }
            .buttonStyle(.gradient)
            .controlSize(.large)
            .disabled(viewModel.selectedItems.isEmpty)
        }
        .padding()
    }

    private var list: some View {
        VStack(spacing: 0) {
            List {
                ForEach(viewModel.groups) { group in
                    Section {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 8) {
                                Text(index == 0 ? "KEEP" : "")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.green)
                                    .frame(width: 40, alignment: .leading)
                                locationChip(item.path)
                                ScanItemRow(item: item, isSelected: viewModel.selectedIDs.contains(item.id)) {
                                    viewModel.toggle(item)
                                }
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                IconChip(symbolName: "doc.on.doc.fill", tint: .yellow, size: 22)
                                Text("\(group.items.count) copies")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                Text("· \(group.sizeEach.formattedBytes) each")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                AIActionButton(title: "Which to keep?", isBusy: loadingGroupID == group.id) {
                                    await explainGroup(group)
                                }
                                Text("\(group.wastedBytes.formattedBytes) wasted")
                                    .font(.system(.callout, design: .rounded).weight(.semibold))
                                    .foregroundStyle(.yellow)
                            }
                            if let explanation = groupExplanations[group.id] {
                                Text(explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                                    .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            Divider()
            selectionFooter
        }
    }
}
