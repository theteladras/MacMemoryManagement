import AppKit
import SwiftUI

/// A drill-down folder tree ("what's actually eating this folder"), sized on demand so opening
/// it never has to walk the whole disk. Rows are checkable and feed the same Review Sheet as
/// every other scanner.
struct StorageTreeView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var viewModel = StorageTreeViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            if viewModel.isLoadingRoot {
                ProgressView("Reading \(viewModel.root.name)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        RootChildrenView(root: viewModel.root)
                            .environmentObject(viewModel)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            Divider()
            footer
        }
        .navigationTitle("Storage Explorer")
        .task {
            await viewModel.refreshRootIfStale()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconChip(symbolName: "list.bullet.indent", tint: .cyan, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(viewModel.root.name)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                    InfoButton(text: "Drill down into any folder to see what's using space inside it. Sizes are calculated on demand as you expand each folder, largest first. Check the boxes next to files or folders you want to remove, then Review & Clean.")
                }
                Text(viewModel.root.url.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let staleness = stalenessLabel {
                Text(staleness)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(viewModel.isRefreshingRoot ? .orange : .secondary)
            }
            Button {
                Task { await viewModel.refreshRootIfStale(force: true) }
            } label: {
                if viewModel.isRefreshingRoot {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshingRoot)
            Button("Choose Folder…") { chooseFolder() }
        }
        .cardStyle(padding: 14)
        .padding([.horizontal, .top])
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRefreshingRoot)
    }

    /// Mirrors `OverviewView`'s staleness label: while a background refresh is running but the
    /// previously-loaded tree is still on screen, say so explicitly instead of letting old numbers
    /// pass as current.
    private var stalenessLabel: String? {
        if viewModel.isRefreshingRoot {
            return "Stale — updating…"
        }
        guard let lastRootLoadDate = viewModel.lastRootLoadDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated " + formatter.localizedString(for: lastRootLoadDate, relativeTo: Date())
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(viewModel.selectedIDs.count) selected")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                Text(viewModel.selectedBytes.formattedBytes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !viewModel.selectedIDs.isEmpty {
                Button("Clear") { viewModel.clearSelection() }
            }
            Button("Review & Clean…") {
                appState.requestReview(ReviewManifest(title: "Clean Selected Items", items: viewModel.selectedItems, onDeleted: { _ in
                    // Explorer is a live filesystem browser, not a cached scan list — the simplest
                    // correct fix is clearing the now-stale selection and re-listing the root
                    // (deeper expanded folders will show correctly next time they're opened).
                    viewModel.clearSelection()
                    Task { await viewModel.refreshRootIfStale(force: true) }
                }))
            }
            .buttonStyle(.gradient)
            .controlSize(.large)
            .disabled(viewModel.selectedIDs.isEmpty)
        }
        .padding()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = viewModel.root.url
        if panel.runModal() == .OK, let url = panel.url {
            Task { await viewModel.setRoot(url) }
        }
    }
}

/// Wraps the root `TreeNode` as its own `@ObservedObject` — without this, SwiftUI never notices
/// when the root's `children`/`listError` change, because a nested object's `@Published`
/// properties don't propagate through a parent view model automatically. This was the actual
/// cause of Storage Explorer looking permanently stuck: the load could finish, but the screen
/// never redrew to show it.
private struct RootChildrenView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var root: TreeNode

    private var timedOutChildren: [TreeNode] {
        (root.children ?? []).filter { $0.sizeStatus == .timedOut }
    }

    var body: some View {
        if root.listError {
            unreadableBanner
        } else if let children = root.children {
            if !timedOutChildren.isEmpty {
                timeoutBanner
            }
            ForEach(children) { child in
                TreeRowView(node: child, depth: 0, parentTotal: max(root.sizeBytes, 1))
            }
        } else if root.isLoadingChildren {
            HStack {
                ProgressView().controlSize(.small)
                Text("Reading \(root.name)…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
        } else {
            ProgressView().frame(maxWidth: .infinity, alignment: .center).padding(.top, 40)
        }
    }

    private var unreadableBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Couldn't read this folder", systemImage: "exclamationmark.triangle.fill")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(.orange)
            Text("Permission was denied. This usually means Full Disk Access is needed for MacMemClean to see this location.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Grant Access…") {
                    withAnimation { appState.selectedSection = .permissions }
                }
                Button("Retry") { root.retry() }
            }
        }
        .cardStyle(padding: 14)
    }

    private var timeoutBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(timedOutChildren.count) folder(s) took too long to read", systemImage: "exclamationmark.triangle.fill")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(.orange)
            Text("Likely needs Full Disk Access — without it, reading a protected folder can trigger a system permission prompt that blocks until answered.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Grant Access…") {
                    withAnimation { appState.selectedSection = .permissions }
                }
                Button("Retry All") {
                    for node in timedOutChildren { node.retry() }
                }
            }
        }
        .cardStyle(padding: 14)
    }
}

private struct TreeRowView: View {
    @EnvironmentObject private var viewModel: StorageTreeViewModel
    @ObservedObject var node: TreeNode
    let depth: Int
    let parentTotal: Int64

    @State private var isExpanded = false

    private var fraction: Double {
        guard parentTotal > 0 else { return 0 }
        return min(1, Double(node.sizeBytes) / Double(parentTotal))
    }

    /// Caps how far rows indent at deep nesting levels — an unbounded `depth * 18` would
    /// eventually crowd out the filename entirely on a very deep tree.
    private var indent: CGFloat { CGFloat(min(depth, 10)) * 16 }
    private var showsSizeBar: Bool { depth < 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            rowContent

            if isExpanded {
                if node.listError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                        Text("Permission denied reading this folder.").font(.caption).foregroundStyle(.secondary)
                        Button("Retry") { node.retry() }.font(.caption)
                    }
                    .padding(.leading, indent + 44)
                } else if let children = node.children {
                    ForEach(children) { child in
                        TreeRowView(node: child, depth: depth + 1, parentTotal: max(node.sizeBytes, 1))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if node.isLoadingChildren {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Reading…").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.leading, indent + 44)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: node.children?.count)
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: indent)

            if node.isDirectory {
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                    if isExpanded {
                        Task { await node.loadChildrenIfNeeded() }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 14)
            }

            Toggle("", isOn: Binding(
                get: { viewModel.isSelected(node) },
                set: { _ in viewModel.toggle(node) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Image(systemName: node.isDirectory ? "folder.fill" : (node.asScanItem.safety.level == .personal ? "photo.fill" : "doc.fill"))
                .foregroundStyle(node.isDirectory ? Color.cyan : Color.secondary)
                .frame(width: 18)

            Text(node.name)
                .font(.system(.callout, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            if !node.isDirectory {
                SafetyBadge(level: node.asScanItem.safety.level, showLabel: false)
            }

            if node.sizeStatus == .timedOut {
                Button {
                    node.retry()
                } label: {
                    Label("Timed out", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Reading this folder timed out — likely needs Full Disk Access. Click to retry.")
            }

            Spacer(minLength: 8)

            if showsSizeBar {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 60, height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(node.isDirectory ? Color.cyan : Color.secondary)
                        .frame(width: 60 * fraction, height: 4)
                        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraction)
                }
                .fixedSize()
            }

            Text(node.sizeStatus == .timedOut ? "—" : node.sizeBytes.formattedBytes)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(viewModel.isSelected(node) ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .help(node.isDirectory ? node.url.path : node.asScanItem.safety.reason)
    }
}
