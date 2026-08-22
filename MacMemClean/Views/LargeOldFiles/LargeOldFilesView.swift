import AppKit
import SwiftUI

struct LargeOldFilesView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = LargeOldFilesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            controls

            Group {
                if viewModel.isScanning {
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
        }
        .cardStyle(padding: 16)
        .padding([.horizontal, .top])
    }

    private var list: some View {
        VStack(spacing: 0) {
            List {
                if !viewModel.largeItems.isEmpty {
                    Section {
                        ForEach(viewModel.largeItems) { item in
                            ScanItemRow(item: item, isSelected: viewModel.selectedIDs.contains(item.id)) {
                                viewModel.toggle(item)
                            }
                        }
                    } header: {
                        SectionHeaderBar(title: "Large Files", symbolName: "doc.badge.arrow.up", tint: .pink, items: viewModel.largeItems)
                    }
                }
                if !viewModel.oldItems.isEmpty {
                    Section {
                        ForEach(viewModel.oldItems) { item in
                            ScanItemRow(item: item, isSelected: viewModel.selectedIDs.contains(item.id)) {
                                viewModel.toggle(item)
                            }
                        }
                    } header: {
                        SectionHeaderBar(title: "Old Files", symbolName: "clock.arrow.circlepath", tint: .brown, items: viewModel.oldItems)
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
                    appState.requestReview(ReviewManifest(title: "Clean Large & Old Files", items: viewModel.selectedItems))
                }
                .buttonStyle(.gradient)
                .controlSize(.large)
                .disabled(viewModel.selectedItems.isEmpty)
            }
            .padding()
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
