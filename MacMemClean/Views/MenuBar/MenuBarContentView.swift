import SwiftUI

/// Content of the menu bar dropdown. Uses `.menuBarExtraStyle(.window)` (a floating custom panel)
/// rather than `.menu` (a native NSMenu) specifically so it can show a real capacity bar at the
/// top — a native menu can only hold text/icon rows, not an arbitrary view. Rows below are
/// hand-styled to still feel like a menu.
struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var overview = OverviewViewModel.shared
    @ObservedObject private var autoCleanup = AutoCleanupSettings.shared
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var isCheckingNow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            storageSummary

            Divider().padding(.vertical, 4)

            row(title: "Open MacMemClean", symbol: "macwindow") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }

            if let manifest = appState.pendingAutoCleanupManifest {
                row(title: "Review Found Items (\(manifest.count), \(manifest.totalBytes.formattedBytes))", symbol: "sparkles", tint: .teal) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                    appState.requestReview(manifest)
                    appState.pendingAutoCleanupManifest = nil
                }
            }

            Divider().padding(.vertical, 4)

            Group {
                row(title: isCheckingNow ? "Checking…" : "Run Cleanup Check Now", symbol: "magnifyingglass") {
                    Task {
                        isCheckingNow = true
                        await BackgroundCleanupScheduler.shared.checkAndRunIfDue(force: true)
                        isCheckingNow = false
                    }
                }
                .disabled(isCheckingNow)

                toggleRow(title: "Automatic Cleanup", symbol: "clock.arrow.circlepath", isOn: $autoCleanup.isEnabled)

                Divider().padding(.vertical, 4)

                toggleRow(title: "Launch at Login", symbol: "power", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        if LaunchAtLoginService.setEnabled(newValue) { launchAtLogin = newValue }
                    }
                ))

                Divider().padding(.vertical, 4)

                row(title: "Quit MacMemClean", symbol: "xmark.circle") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(8)
        .frame(width: 280)
        .task {
            await overview.loadSummary()
        }
    }

    private var storageSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconChip(symbolName: "internaldrive.fill", tint: .indigo, size: 22, useBrandGradient: true)
                Text("Storage")
                    .font(.system(.callout, design: .rounded).weight(.bold))
                Spacer()
                Text(overview.summary.totalBytes > 0 ? "\(overview.summary.freeBytes.formattedBytes) free" : "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SegmentedCapacityBar(segments: capacitySegments, height: 10)

            if overview.summary.totalBytes > 0 {
                Text("\(overview.summary.usedBytes.formattedBytes) of \(overview.summary.totalBytes.formattedBytes) used")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    private var capacitySegments: [SegmentedCapacityBar.Segment] {
        let total = max(overview.summary.totalBytes, 1)
        var segments = overview.summary.breakdown.map {
            SegmentedCapacityBar.Segment(id: $0.name, fraction: Double($0.bytes) / Double(total), color: $0.tint)
        }
        if overview.summary.otherBytes > 0 {
            segments.append(SegmentedCapacityBar.Segment(id: "other", fraction: Double(overview.summary.otherBytes) / Double(total), color: .gray))
        }
        return segments
    }

    private func row(title: String, symbol: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 16)
                Text(title)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(.primary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(.callout, design: .rounded))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }
}
