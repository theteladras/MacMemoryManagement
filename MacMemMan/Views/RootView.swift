import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var overviewVM = OverviewViewModel.shared
    @AppStorage("sidebar.isExpanded") private var isSidebarExpanded: Bool = true
    @State private var titleBarHeight: CGFloat = 38
    @Environment(\.openWindow) private var openWindow

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
        ZStack(alignment: .top) {
            // Behind everything, all the time — the sidebar and detail area both sit on a
            // translucent material (`.regularMaterial` / `.ultraThinMaterial`) specifically so
            // this shows through as a soft, drifting tint instead of a flat window background.
            AnimatedGradientBackground()

            // Only visible because the window's title bar is made transparent below — fills the
            // title bar strip itself left-to-right in proportion to disk usage.
            TitleBarCapacityFill(fraction: overviewVM.summary.usedFraction, height: titleBarHeight)

            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: isSidebarExpanded ? expandedWidth : collapsedWidth)

                Divider()

                NavigationStack {
                    detailView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
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
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSidebarExpanded)
        .animation(.easeInOut(duration: 0.4), value: overviewVM.summary.usedFraction)
        .background(
            WindowAccessor { window in
                window.titlebarAppearsTransparent = true
                titleBarHeight = window.frame.height - window.contentLayoutRect.height
            }
        )
        .sheet(item: $appState.pendingManifest) { manifest in
            ReviewSheet(manifest: manifest)
        }
        .onAppear {
            // See `AppState.openMainWindow` — the menu bar controller lives outside any SwiftUI
            // `Scene`, so it can't resolve `@Environment(\.openWindow)` itself; this is the one
            // place in the app where that environment value is actually valid.
            appState.openMainWindow = { openWindow(id: "main") }
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
            case .multiUser:
                MultiUserView()
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
