import Photos
import SwiftUI
import UserNotifications

/// A first-class, always-reachable home for permissions — so if Full Disk Access was skipped or
/// declined during first launch, there's an obvious place to come back and grant it later rather
/// than it being buried inside Settings.
struct PermissionsView: View {
    // Held directly, not read through `appState.permissions` — a nested object's own `@Published`
    // changes don't propagate through a parent's `@EnvironmentObject` subscription, so every row
    // below needs its own live subscription to actually update when a permission changes. See
    // `PermissionsManager`'s doc comment for how this was proven (not guessed) via debug logging.
    @ObservedObject private var permissions = PermissionsManager.shared
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                fullDiskAccessRow
                notificationsRow
                photosRow
                launchAtLoginRow
                folderAndMediaAccessCard
                adminAuthorizationCard
                explainerCard
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Permissions")
        .onAppear { permissions.refresh() }
        // `.onAppear` only fires once, when this view is first inserted — it does not refire when
        // you alt-tab back from System Settings after granting a permission there, so without this
        // the screen would keep showing stale "Not granted" state until the view was torn down and
        // recreated (e.g. switching sidebar sections and back).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private var fullDiskAccessRow: some View {
        PermissionInfoRow(
            symbolName: "internaldrive.fill",
            tint: .indigo,
            title: "Full Disk Access",
            description: "Lets MacMemMan scan system caches, logs, and other apps' leftover files. Without it, MacMemMan still cleans your own files (Downloads, Documents, per-app caches) — system-wide locations are just skipped. macOS doesn't let an app grant or check this itself, and an ad-hoc-signed build like this one can lose the grant on every rebuild — System Settings is the source of truth for whether it's actually on.",
            buttonLabel: "Open Full Disk Access Settings…",
            action: { permissions.openFullDiskAccessSettings() }
        )
    }

    private var notificationsRow: some View {
        let status = permissions.notificationStatus
        return PermissionInfoRow(
            symbolName: "bell.badge.fill",
            tint: .pink,
            title: "Notifications",
            description: "Lets Automatic Cleanup (Settings) let you know when it finds something to review, even if MacMemMan's window is closed. Once macOS has asked once, only System Settings can change the answer.",
            buttonLabel: status == .notDetermined ? "Allow Notifications…" : "Open Notification Settings…",
            action: {
                if status == .notDetermined {
                    permissions.requestNotifications()
                } else {
                    permissions.openNotificationSettings()
                }
            }
        )
    }

    private var photosRow: some View {
        let status = permissions.photosStatus
        return PermissionInfoRow(
            symbolName: "photo.on.rectangle.angled",
            tint: .purple,
            title: "Photos Library",
            description: "Needed when a scan (Duplicates, By File Type, Last 24 Hours) walks into your Photos Library — without it, that content is skipped rather than reported inaccurately. Once macOS has asked once, only System Settings can change the answer.",
            buttonLabel: status == .notDetermined ? "Allow Photos Access…" : "Open Photos Settings…",
            action: {
                AppDebugLog.write("photosRow tapped: status=\(status.rawValue)")
                if status == .notDetermined {
                    permissions.requestPhotos()
                } else {
                    permissions.openPhotosSettings()
                }
            }
        )
    }

    /// Unlike Full Disk Access/Notifications, this one is a genuine, immediate in-app toggle —
    /// `SMAppService` registration isn't gated by a system privacy prompt, so flipping it here
    /// actually takes effect right away, no detour to System Settings required.
    private var launchAtLoginRow: some View {
        Button {
            let newValue = !launchAtLogin
            if LaunchAtLoginService.setEnabled(newValue) { launchAtLogin = newValue }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                IconChip(symbolName: "power.circle.fill", tint: launchAtLogin ? .green : .teal, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Launch at Login").font(.system(.title3, design: .rounded).weight(.bold))
                        Spacer()
                        SwitchIndicator(isOn: launchAtLogin)
                    }
                    Text(launchAtLogin ? "Enabled" : "Disabled")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(launchAtLogin ? .green : .secondary)
                    Text("MacMemMan lives in the menu bar so Automatic Cleanup keeps checking even with the window closed — this starts it automatically when you log in.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Fully controlled in-app — tapping flips it immediately, no System Settings detour.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .cardStyle()
        .animation(.easeInOut(duration: 0.25), value: launchAtLogin)
    }

    /// Not a toggle-styled row like the others above — macOS has no API to check or pre-grant
    /// these, only per-folder prompts that fire the first time a scan actually touches Desktop,
    /// Documents, Downloads, Pictures, or the Music folder (you've likely seen a few of these
    /// already, one per folder, the first time "Last 24 Hours" or "By File Type" ran). This card
    /// exists so those aren't a mystery, and so there's still a way back to review or revoke them.
    private var folderAndMediaAccessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                IconChip(symbolName: "folder.badge.questionmark", tint: .orange, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder & Media Access").font(.system(.title3, design: .rounded).weight(.bold))
                    Text("Requested per folder, as needed")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Scans that look at your personal content (Desktop, Documents, Downloads, Pictures, Music) trigger a separate macOS prompt the first time each one is actually touched — there's no API for an app to check or pre-grant these ahead of time, so they can't be listed here as granted or not the way Full Disk Access or Photos can.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button("Review Files & Folders…") { permissions.openFilesAndFoldersSettings() }
                Button("Review Media & Apple Music…") { permissions.openMediaLibrarySettings() }
                Spacer()
            }
        }
        .cardStyle()
    }

    /// Not a toggle — there's nothing to grant or revoke ahead of time. Multi-user cleanup
    /// (Other Users) costs a real macOS admin-password prompt every time it scans or deletes;
    /// this card exists purely so that requirement isn't a surprise the first time it fires.
    private var adminAuthorizationCard: some View {
        HStack(alignment: .top, spacing: 14) {
            IconChip(symbolName: "person.badge.key.fill", tint: .red, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Admin Authorization").font(.system(.title3, design: .rounded).weight(.bold))
                Text("Requested per action")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Cleaning up another account's files (Other Users) needs your admin password — macOS has no way for an app to read or remove another account's files without it. There's nothing to pre-grant here: every scan and every cleanup in that section prompts fresh.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Why MacMemMan asks for this")
                .font(.system(.headline, design: .rounded))

            explainerRow(symbol: "lock.open.fill", tint: .indigo, title: "Not sandboxed, on purpose", body: "MacMemMan is distributed outside the App Store so it can see the same locations DaisyDisk or CleanMyMac can — the App Store sandbox would only let it see its own files.")
            explainerRow(symbol: "trash.fill", tint: .teal, title: "Nothing happens automatically", body: "Full Disk Access only lets the app read and list files. Every deletion still goes through the Review screen, and defaults to moving items to the Trash.")
            explainerRow(symbol: "hand.raised.fill", tint: .pink, title: "You're always in control", body: "You can revoke either of these at any time in System Settings — the app just quietly does less without them, it never breaks.")
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

/// Deliberately *not* a live on/off indicator. It used to be — but macOS never lets an app flip
/// or reliably read back its own TCC permission (Full Disk Access, Notifications/Photos once
/// decided) from in-process, and for an ad-hoc-signed build that state can silently reset on every
/// rebuild (each build gets a new code signature, so TCC treats it as a different app). Showing a
/// green/red status here was actively misleading: granted-but-shown-as-off, with no way for the
/// user to tell whether the app was wrong or the permission really was off. System Settings is the
/// one place that's always right, so every row just explains what the permission is for and hands
/// you straight there (or triggers the real system prompt directly, if nothing's been decided yet).
private struct PermissionInfoRow: View {
    let symbolName: String
    let tint: Color
    let title: String
    let description: String
    let buttonLabel: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                IconChip(symbolName: symbolName, tint: tint, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.title3, design: .rounded).weight(.bold))
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button(buttonLabel, action: action)
                Spacer()
            }
        }
        .cardStyle()
    }
}

private struct SwitchIndicator: View {
    let isOn: Bool
    var body: some View {
        Capsule()
            .fill(isOn ? Color.green : Color.secondary.opacity(0.35))
            .frame(width: 44, height: 26)
            .overlay(
                Circle()
                    .fill(.white)
                    .padding(2)
                    .frame(width: 26, height: 26)
                    .offset(x: isOn ? 9 : -9)
                    .shadow(radius: 1)
            )
    }
}
