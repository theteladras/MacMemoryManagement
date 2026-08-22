import SwiftUI

/// A first-class, always-reachable home for permissions — so if Full Disk Access was skipped or
/// declined during first launch, there's an obvious place to come back and grant it later rather
/// than it being buried inside Settings.
struct PermissionsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusCard
                explainerCard
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Permissions")
        .onAppear { appState.permissions.refresh() }
    }

    private var granted: Bool { appState.permissions.hasFullDiskAccess }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                IconChip(symbolName: granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill", tint: granted ? .green : .orange, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Full Disk Access")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text(granted ? "Granted" : "Not granted")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(granted ? .green : .orange)
                }
                Spacer()
            }

            Text(granted
                 ? "MacMemClean can scan system caches, logs, and other apps' leftover files."
                 : "Without this, MacMemClean can still clean your own files (Downloads, Documents, per-app caches) — but system-wide caches, logs, and other apps' leftovers will be skipped.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if !granted {
                    Button {
                        appState.permissions.openFullDiskAccessSettings()
                    } label: {
                        Label("Open System Settings", systemImage: "gearshape.fill")
                    }
                    .buttonStyle(.gradient)
                    .controlSize(.large)
                }
                Button {
                    withAnimation { appState.permissions.refresh() }
                } label: {
                    Label("Re-check", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
            }

            if !granted {
                Label("After enabling it in System Settings, you may need to relaunch MacMemClean for it to take full effect.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .animation(.easeInOut(duration: 0.25), value: granted)
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Why MacMemClean asks for this")
                .font(.system(.headline, design: .rounded))

            explainerRow(symbol: "lock.open.fill", tint: .indigo, title: "Not sandboxed, on purpose", body: "MacMemClean is distributed outside the App Store so it can see the same locations DaisyDisk or CleanMyMac can — the App Store sandbox would only let it see its own files.")
            explainerRow(symbol: "trash.fill", tint: .teal, title: "Nothing happens automatically", body: "Full Disk Access only lets the app read and list files. Every deletion still goes through the Review screen, and defaults to moving items to the Trash.")
            explainerRow(symbol: "hand.raised.fill", tint: .pink, title: "You're always in control", body: "You can revoke this at any time in System Settings → Privacy & Security → Full Disk Access — the app will just skip system locations again.")
        }
        .cardStyle()
    }

    private func explainerRow(symbol: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconChip(symbolName: symbol, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.callout, design: .rounded).weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
