import SwiftUI

/// Keeps the app (and its menu bar icon) alive after the main window is closed — the standard
/// behavior for a menu-bar-resident utility app. Without this, SwiftUI quits the whole app the
/// moment the last window closes, which would silently kill the background auto-cleanup scheduler.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Deferred by one run-loop tick, not called synchronously here — `NSApp.setActivationPolicy`
        // called directly inside `applicationDidFinishLaunching` races `MenuBarExtra`'s own AppKit
        // setup on this SwiftUI/AppKit lifecycle, and can leave its status item registered (reserving
        // its spot in the menu bar) but with a blank, never-drawn icon. Applies whatever was
        // persisted last time — if menu-bar-only mode was on, the Dock icon needs to be hidden again
        // from the first frame, not just when the toggle is flipped.
        DispatchQueue.main.async {
            AppSettings.shared.applyActivationPolicy()
        }
    }
}

@main
struct MacMemManApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    appState.startBackgroundServices()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.pendingAutoCleanupManifest != nil ? "wind.circle.fill" : "wind")
        }
        // `.window` (a floating custom panel) instead of `.menu` (a native NSMenu) — a native menu
        // can only hold text/icon rows, it can't host an arbitrary view like the capacity bar.
        .menuBarExtraStyle(.window)
    }
}
