import SwiftUI

struct JunkScanView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = JunkScanViewModel()

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

            Group {
                if viewModel.isScanning {
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
                } else if viewModel.items.isEmpty {
                    EmptyStateView(symbolName: "checkmark.circle", title: "All Clean", message: "No junk found in known locations.")
                        .transition(.opacity)
                } else {
                    list
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.isScanning)
            .animation(.easeInOut(duration: 0.25), value: viewModel.hasScanned)
        }
        .navigationTitle("Caches & Junk")
    }

    private var toolbar: some View {
        HStack {
            if viewModel.hasScanned && !viewModel.isScanning {
                Text("\(viewModel.items.count) items found")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Select All") { viewModel.selectAll() }
                Button("Select None") { viewModel.selectNone() }
                Button {
                    Task { await viewModel.scan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            } else {
                Spacer()
            }
        }
        .padding()
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
                    appState.requestReview(ReviewManifest(title: "Clean Junk & Caches", items: viewModel.selectedItems))
                }
                .buttonStyle(.gradient)
                .controlSize(.large)
                .disabled(viewModel.selectedItems.isEmpty)
            }
            .padding()
        }
    }
}
