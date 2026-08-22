import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DuplicatesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Duplicates").font(.system(.title3, design: .rounded).weight(.bold))
                InfoButton(text: "Compares files by content (size, then a hash) across Downloads, Documents & Desktop. The oldest copy in each set is suggested as the \"KEEP\", but personal photos, videos & documents are never pre-selected — only generic duplicates are.")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            toolbar

            Group {
                if viewModel.isScanning {
                    ProgressView("Comparing files in Downloads, Documents & Desktop…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if !viewModel.hasScanned {
                    EmptyStateView(
                        symbolName: "doc.on.doc",
                        title: "Duplicate Files",
                        message: "Finds exact duplicate files in Downloads, Documents & Desktop. Personal photos, videos & documents are always left for you to select by hand.",
                        actionTitle: "Scan",
                        action: { Task { await viewModel.scan() } }
                    )
                    .transition(.opacity)
                } else if viewModel.groups.isEmpty {
                    EmptyStateView(symbolName: "checkmark.circle", title: "No Duplicates Found", message: "No exact duplicate files were found.")
                        .transition(.opacity)
                } else {
                    list
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
            if viewModel.hasScanned && !viewModel.isScanning {
                Text("\(viewModel.groups.count) duplicate sets")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                Text("·").foregroundStyle(.secondary)
                Text("\(viewModel.wastedBytes.formattedBytes) wasted")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
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
                                ScanItemRow(item: item, isSelected: viewModel.selectedIDs.contains(item.id)) {
                                    viewModel.toggle(item)
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 8) {
                            IconChip(symbolName: "doc.on.doc.fill", tint: .yellow, size: 22)
                            Text("\(group.items.count) copies")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            Text("· \(group.sizeEach.formattedBytes) each")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(group.wastedBytes.formattedBytes) wasted")
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                                .foregroundStyle(.yellow)
                        }
                        .padding(.vertical, 4)
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
                    appState.requestReview(ReviewManifest(title: "Clean Duplicate Files", items: viewModel.selectedItems))
                }
                .buttonStyle(.gradient)
                .controlSize(.large)
                .disabled(viewModel.selectedItems.isEmpty)
            }
            .padding()
        }
    }
}
