import AppKit
import SwiftUI

private extension SidebarSection {
    var tint: Color {
        switch self {
        case .overview: return .indigo
        case .explorer: return .cyan
        case .junk: return .teal
        case .largeOld: return .pink
        case .duplicates: return .yellow
        case .compression: return .teal
        case .uninstaller: return .purple
        case .history: return .green
        case .permissions: return .orange
        case .settings: return .gray
        }
    }
}

/// Custom-drawn nav list (not `List(selection:)`) so the selected row can be a bold gradient
/// pill — the app's signature visual instead of the default macOS blue highlight.
///
/// Width is a controlled binary state (expanded/collapsed), not a freely draggable column: every
/// row obeys the same state together, rather than each row independently deciding — via
/// `ViewThatFits` — whether its own label still fits, which used to let some rows show text while
/// narrower ones next to them collapsed to icon-only. `RootView` hosts this in a plain fixed-width
/// `HStack` slot (not `NavigationSplitView`, which auto-injects its own sidebar toggle into the
/// toolbar with no supported way to remove it on this SDK) — that fixed frame is what actually
/// makes the sidebar unresizable, and `RootView`'s own single `ToolbarItem` is the only collapse
/// control that exists, reading/writing the same `isExpanded` key as this view.
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("sidebar.isExpanded") private var isExpanded: Bool = true

    private let mainSections: [SidebarSection] = [.overview, .explorer, .junk, .largeOld, .duplicates, .compression, .uninstaller, .history]
    private let footerSections: [SidebarSection] = [.permissions, .settings]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(mainSections) { section in
                        sidebarRow(section)
                    }

                    Divider().padding(.vertical, 8)

                    ForEach(footerSections) { section in
                        sidebarRow(section)
                    }
                }
                .padding(.horizontal, isExpanded ? 10 : 8)
                .padding(.top, 4)
            }
        }
        .background(.regularMaterial)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
        .safeAreaInset(edge: .bottom) {
            if !appState.permissions.hasFullDiskAccess {
                fdaNudge
                    .padding(.horizontal, isExpanded ? 10 : 8)
                    .padding(.bottom, 8)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            appIcon
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Text("MacMemClean")
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .lineLimit(1)
                    Text("Storage Cleanup")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var appIcon: some View {
        // `applicationIconImage` returns the raw square source — macOS only applies its rounded
        // "squircle" mask automatically in the Dock/Finder, not when we draw it ourselves in-app.
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 34 * 0.22, style: .continuous))
    }

    private func sidebarRow(_ section: SidebarSection) -> some View {
        let isSelected = appState.selectedSection == section
        let needsAttention = section == .permissions && !appState.permissions.hasFullDiskAccess

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appState.selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                rowIcon(section, isSelected: isSelected, needsAttention: needsAttention)
                if isExpanded {
                    Text(section.rawValue)
                        .font(.system(.body, design: .rounded).weight(isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .white : Color(nsColor: .labelColor))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            .padding(.horizontal, isExpanded ? 12 : 0)
            .padding(.vertical, 9)
            .background(
                isSelected ? AnyShapeStyle(Design.brandGradient) : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous)
            )
            .shadow(color: isSelected ? .purple.opacity(0.35) : .clear, radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .help(section.rawValue)
    }

    private func rowIcon(_ section: SidebarSection, isSelected: Bool, needsAttention: Bool) -> some View {
        Image(systemName: section.symbolName)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(isSelected ? .white : Color(nsColor: .labelColor))
            .frame(width: 20)
            .overlay(alignment: .topTrailing) {
                if needsAttention {
                    Circle().fill(Color.orange).frame(width: 6, height: 6).offset(x: 4, y: -2)
                }
            }
    }

    private var fdaNudge: some View {
        Button {
            withAnimation { appState.selectedSection = .permissions }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if isExpanded {
                    Text("Grant Full Disk Access")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
        }
        .buttonStyle(.plain)
        .padding(isExpanded ? 10 : 8)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: Design.rowRadius))
        .help("Grant Full Disk Access")
    }
}
