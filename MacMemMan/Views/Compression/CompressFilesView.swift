import AppKit
import SwiftUI

/// Transparent, lossless compression (via `ditto --hfsCompression`) for compressible file types —
/// files stay byte-identical when opened, they just take less space on disk. A separate flow from
/// every other scanner in the app: nothing here is ever deleted.
struct CompressFilesView: View {
    @ObservedObject private var viewModel = CompressionViewModel.shared
    @State private var confirmingCompress = false
    @State private var aiSummary: String?
    @State private var isSummarizing = false

    var body: some View {
        VStack(spacing: 0) {
            header
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

            Group {
                // Cached/previous results take priority over the scanning spinner — see
                // `JunkScanView` for the same pattern and why.
                if viewModel.isScanning && !viewModel.hasScanned {
                    ProgressView("Scanning \(viewModel.scanRoot?.lastPathComponent ?? "")…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if let result = viewModel.result {
                    resultSummary(result)
                        .transition(.opacity)
                } else if viewModel.scanRoot == nil {
                    EmptyStateView(
                        symbolName: "folder.badge.plus",
                        title: "Choose a Folder to Analyze",
                        message: "Pick the folder you want scanned for lossless compression candidates — text, logs, source code, uncompressed audio/images and similar files that shrink well without changing byte-for-byte. You choose which results to actually compress.",
                        actionTitle: "Choose Folder…",
                        action: { chooseFolder() }
                    )
                    .transition(.opacity)
                } else if !viewModel.hasScanned {
                    EmptyStateView(
                        symbolName: "archivebox",
                        title: "Compress Files",
                        message: "Hit Scan to look for compression candidates in this folder. The file stays byte-identical, just smaller on disk.",
                        actionTitle: "Scan",
                        action: { Task { await viewModel.scan() } }
                    )
                    .transition(.opacity)
                } else if viewModel.candidates.isEmpty {
                    EmptyStateView(symbolName: "checkmark.circle", title: "Nothing To Compress", message: "No good compression candidates found in this folder.")
                        .transition(.opacity)
                } else {
                    list
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.isScanning)
            .animation(.easeInOut(duration: 0.25), value: viewModel.hasScanned)
            .animation(.easeInOut(duration: 0.25), value: viewModel.result != nil)
        }
        .navigationTitle("Compress Files")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Compress Files").font(.system(.title3, design: .rounded).weight(.bold))
            InfoButton(text: "Uses macOS's own transparent APFS compression (the same mechanism used for system files) — compressed files open and behave exactly as before, they just use less disk space. Only applied to file types that actually compress well; already-compressed formats (photos, videos, zips) are skipped. Each file is verified byte-for-byte identical before the original is replaced.")
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill").foregroundStyle(.teal)
                    if let scanRoot = viewModel.scanRoot {
                        Text(scanRoot.path)
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("No folder selected")
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                    Button(viewModel.scanRoot == nil ? "Choose Folder…" : "Choose…") { chooseFolder() }
                    Spacer()
                    Button {
                        Task { await viewModel.scan() }
                    } label: {
                        Label(viewModel.isScanning ? "Scanning…" : "Scan", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.gradient)
                    .disabled(viewModel.isScanning || viewModel.scanRoot == nil)
                    .help(viewModel.scanRoot == nil ? "Choose a folder first" : "")
                }
                Text("Scan looks inside the chosen folder and every subfolder underneath it (skipping Library, node_modules, .git, and Trash).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Only include files of at least").foregroundStyle(.secondary)
                    Slider(value: $viewModel.minSizeMB, in: 1...200, step: 1)
                        .frame(width: 200)
                    Text("\(Int(viewModel.minSizeMB)) MB")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .frame(width: 60, alignment: .leading)
                }
                .font(.callout)
                Text("Smaller files barely shrink and aren't worth the overhead — raise this to focus on the biggest wins, lower it to catch more files. There's no maximum; every file above this size is considered, however large.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle(padding: 16)
        .padding([.horizontal, .top])
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(viewModel.candidates.count) candidates found")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Select All") { viewModel.selectAll() }
                Button("Select None") { viewModel.selectNone() }
                Button {
                    Task { await summarize() }
                } label: {
                    if isSummarizing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Suggesting…")
                        }
                    } else {
                        Label("Suggest", systemImage: "sparkles")
                    }
                }
                // Visible either way, but only enabled once AI Assist is actually configured —
                // unlike most AI buttons in the app (which open key setup on tap), this one just
                // stays disabled with an explanatory tooltip, matching the Review Sheet's "AI
                // Review" button.
                .disabled(isSummarizing || !AIAssistService.isAvailable || viewModel.candidates.isEmpty)
                .help(AIAssistService.isAvailable
                      ? "Ask AI which candidates are the best first picks for freeing up space"
                      : "Add an Anthropic API key in Settings to enable this")
            }
            .padding(.horizontal)
            .padding(.top, 8)

            List {
                ForEach(viewModel.candidates) { candidate in
                    row(candidate)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(viewModel.selectedCandidates.count) selected")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                    Text("~\(viewModel.selectedEstimatedSavings.formattedBytes) estimated savings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.isCompressing {
                    ProgressView(value: Double(viewModel.progress.done), total: Double(max(viewModel.progress.total, 1)))
                        .frame(width: 140)
                    Text("\(viewModel.progress.done)/\(viewModel.progress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Compress Selected…") { confirmingCompress = true }
                        .buttonStyle(.gradient)
                        .controlSize(.large)
                        .disabled(viewModel.selectedCandidates.isEmpty)
                        .confirmationDialog(
                            "Compress \(viewModel.selectedCandidates.count) file(s)?",
                            isPresented: $confirmingCompress,
                            titleVisibility: .visible
                        ) {
                            Button("Compress") { Task { await viewModel.compressSelected() } }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Each file is verified to be byte-for-byte identical before replacing the original — nothing changes about how these files open or work, they'll just use less disk space.")
                        }
                }
            }
            .padding()
        }
    }

    private func row(_ candidate: CompressionCandidate) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { viewModel.selectedIDs.contains(candidate.id) },
                set: { _ in viewModel.toggle(candidate) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            IconChip(symbolName: "doc.fill", tint: .teal, size: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayName).font(.system(.body, design: .rounded)).lineLimit(1)
                Text(candidate.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text("~\(candidate.estimatedSavingsBytes.formattedBytes) est.")
                .font(.caption)
                .foregroundStyle(.teal)

            SizeBadge(bytes: candidate.sizeBytes, tint: .teal)
        }
        .padding(.vertical, 3)
        .opacity(viewModel.selectedIDs.contains(candidate.id) ? 1 : 0.5)
    }

    private func resultSummary(_ result: CompressionService.Result) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("\(result.savedBytes.formattedBytes) saved")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("\(result.successes.count) files compressed" + (result.failures.isEmpty ? "" : ", \(result.failures.count) skipped"))
                .foregroundStyle(.secondary)

            if !result.failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.failures, id: \.candidate.id) { failure in
                            Text("\(failure.candidate.displayName): \(failure.reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }

            Button("Scan Again") { Task { await viewModel.scan() } }
                .buttonStyle(.gradient)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func summarize() async {
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            aiSummary = try await AIAssistService.summarizeCompression(candidates: viewModel.candidates)
        } catch {
            aiSummary = error.localizedDescription
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
