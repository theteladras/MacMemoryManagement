import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("sidebar.isExpanded") private var isSidebarExpanded: Bool = true

    private let expandedWidth: CGFloat = 240
    private let collapsedWidth: CGFloat = 68

    var body: some View {
        // A manually-composed split, not `NavigationSplitView` — that view auto-injects its own
        // native sidebar toggle into the toolbar with no supported way to suppress it on this SDK,
        // which is exactly what produced two competing toggle buttons earlier. A plain `HStack`
        // with a fixed-width sidebar has no such built-in control, so the only toggle that exists
        // is the one `ToolbarItem` declared below — and a fixed `.frame(width:)` (not a
        // `NavigationSplitView` column) also means there's nothing to drag-resize in the first
        // place. `NavigationStack` wraps only the detail side so each screen's `.navigationTitle`
        // still renders in the window's title bar as before.
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: isSidebarExpanded ? expandedWidth : collapsedWidth)

            Divider()

            NavigationStack {
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isSidebarExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: isSidebarExpanded ? "sidebar.left" : "sidebar.right")
                            }
                            .help(isSidebarExpanded ? "Collapse Sidebar" : "Expand Sidebar")
                        }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSidebarExpanded)
        .sheet(item: $appState.pendingManifest) { manifest in
            ReviewSheet(manifest: manifest)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        Group {
            switch appState.selectedSection {
            case .overview:
                OverviewView()
            case .explorer:
                StorageTreeView()
            case .junk:
                JunkScanView()
            case .largeOld:
                LargeOldFilesView()
            case .duplicates:
                DuplicatesView()
            case .compression:
                CompressFilesView()
            case .uninstaller:
                UninstallerView()
            case .history:
                DeletionHistoryView()
            case .permissions:
                PermissionsView()
            case .settings:
                SettingsView()
            }
        }
        .id(appState.selectedSection)
        .transition(.opacity.combined(with: .move(edge: .leading)))
        .animation(.easeOut(duration: 0.2), value: appState.selectedSection)
    }
}

extension ReviewManifest: Identifiable {
    var id: String { title }
}
