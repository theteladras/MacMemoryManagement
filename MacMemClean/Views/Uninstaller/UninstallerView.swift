import AppKit
import SwiftUI

struct UninstallerView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = UninstallerViewModel()

    var body: some View {
        HSplitView {
            appListColumn
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            detailColumn
                .frame(minWidth: 380, maxWidth: .infinity)
        }
        .navigationTitle("Applications")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                InfoButton(text: "Lists apps in /Applications and ~/Applications. Selecting one searches for its leftover Application Support, Caches, Preferences, Saved State, Logs, and Container files elsewhere on disk, grouped by kind, with each file's exact location and safety rating — so you can clear just the safe leftovers, or remove the app and everything at once.")
            }
        }
        .task {
            if viewModel.apps.isEmpty {
                await viewModel.loadApps()
            }
        }
    }

    private var appListColumn: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading applications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.apps, selection: Binding(
                    get: { viewModel.selectedApp?.id },
                    set: { id in
                        if let app = viewModel.apps.first(where: { $0.id == id }) {
                            Task { await viewModel.selectApp(app) }
                        }
                    }
                )) { app in
                    HStack(spacing: 10) {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(.system(.body, design: .rounded)).lineLimit(1)
                            Text(app.lastUsedLabel)
                                .font(.caption2)
                                .foregroundStyle(app.isStale ? .orange : .secondary)
                        }
                        Spacer()
                        Text(app.sizeBytes.formattedBytes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(app.id)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let app = viewModel.selectedApp {
            if viewModel.isLoadingPlan {
                ProgressView("Finding leftover files for \(app.name)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let plan = viewModel.plan {
                PlanDetailView(plan: plan)
                    .environmentObject(viewModel)
            } else {
                EmptyStateView(symbolName: "app.badge.checkmark", title: app.name, message: "No details available.")
            }
        } else {
            EmptyStateView(
                symbolName: "square.grid.2x2",
                title: "Uninstall Applications",
                message: "Select an app on the left to see exactly which files it left behind, where they live, and which are safe to clear."
            )
        }
    }
}

private struct PlanDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: UninstallerViewModel
    let plan: UninstallPlan

    private var bundleItem: ScanItem? { plan.items.first { $0.path == plan.app.bundlePath } }
    private var leftoverItems: [ScanItem] { plan.items.filter { $0.path != plan.app.bundlePath } }

    private var groupedLeftovers: [(reason: String, items: [ScanItem])] {
        let grouped = Dictionary(grouping: leftoverItems, by: \.reason)
        return grouped.keys.sorted().map { key in (key, grouped[key]!.sorted { $0.sizeBytes > $1.sizeBytes }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                if let icon = plan.app.icon {
                    Image(nsImage: icon).resizable().frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.app.name).font(.system(.title3, design: .rounded).weight(.semibold))
                    if let id = plan.app.bundleIdentifier {
                        Text(id).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(plan.app.lastUsedLabel)
                        .font(.caption)
                        .foregroundStyle(plan.app.isStale ? .orange : .secondary)
                }
                Spacer()
                SizeBadge(bytes: plan.totalBytes, tint: .purple)
            }
            .padding()

            Divider()

            if leftoverItems.isEmpty {
                EmptyStateView(symbolName: "checkmark.circle", title: "No Leftovers Found", message: "This app doesn't appear to have left anything behind outside its own bundle.")
            } else {
                List {
                    if let bundleItem {
                        Section {
                            leftoverRow(bundleItem, selectable: false)
                        } header: {
                            Text("Application Bundle").font(.system(.subheadline, design: .rounded).weight(.semibold))
                        }
                    }
                    ForEach(groupedLeftovers, id: \.reason) { group in
                        Section {
                            ForEach(group.items) { item in
                                leftoverRow(item, selectable: true)
                            }
                        } header: {
                            SectionHeaderBar(title: group.reason, symbolName: symbolName(for: group.reason), tint: .purple, items: group.items)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            Divider()
            footer
        }
    }

    private func leftoverRow(_ item: ScanItem, selectable: Bool) -> some View {
        HStack(spacing: 10) {
            if selectable {
                Toggle("", isOn: Binding(
                    get: { viewModel.selectedLeftoverIDs.contains(item.id) },
                    set: { _ in viewModel.toggleLeftover(item) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            } else {
                Image(systemName: "app.fill").foregroundStyle(.purple).frame(width: 14)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(.callout, design: .rounded))
                        .lineLimit(1)
                    SafetyBadge(level: item.safety.level)
                }
                Text(item.path.path)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.path])
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")

            Text(item.sizeBytes.formattedBytes)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .opacity(selectable && !viewModel.selectedLeftoverIDs.contains(item.id) ? 0.55 : 1)
        .help(item.safety.reason)
    }

    private func symbolName(for reason: String) -> String {
        switch reason {
        case "Cache": return "internaldrive"
        case "Logs": return "doc.text.magnifyingglass"
        case "Preferences": return "slider.horizontal.3"
        case "Application Support": return "folder.fill"
        case "Saved State": return "clock.arrow.circlepath"
        case "Container", "Group Container": return "shippingbox.fill"
        case "HTTP Storage", "WebKit Data": return "network"
        default: return "doc.fill"
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(viewModel.selectedLeftoverItems.count) selected")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                Text(viewModel.selectedLeftoverBytes.formattedBytes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !leftoverItems.isEmpty {
                Button("Clean Selected…") {
                    appState.requestReview(ReviewManifest(title: "Clean \(plan.app.name) Leftovers", items: viewModel.selectedLeftoverItems))
                }
                .buttonStyle(.gradient)
                .controlSize(.large)
                .disabled(viewModel.selectedLeftoverItems.isEmpty)
            }
            Button("Uninstall Everything…") {
                appState.requestReview(ReviewManifest(title: "Uninstall \(plan.app.name)", items: plan.items))
            }
            .buttonStyle(.gradient(Design.dangerGradient))
            .controlSize(.large)
        }
        .padding()
    }
}
