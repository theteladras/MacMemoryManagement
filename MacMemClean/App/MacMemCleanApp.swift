import SwiftUI

/// Keeps the app (and its menu bar icon) alive after the main window is closed — the standard
/// behavior for a menu-bar-resident utility app. Without this, SwiftUI quits the whole app the
/// moment the last window closes, which would silently kill the background auto-cleanup scheduler.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct MacMemCleanApp: App {
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
