import SwiftUI

/// Keeps the app (and its menu bar icon) alive after the main window is closed — the standard
/// behavior for a menu-bar-resident utility app. Without this, SwiftUI quits the whole app the
/// moment the last window closes, which would silently kill the background auto-cleanup scheduler.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let menuBarController = MenuBarController()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Installed here, deliberately not as a SwiftUI `MenuBarExtra` scene — see
        // `MenuBarController` for why. `attach(appState:)` is called separately, from
        // `RootView.onAppear`, once `AppState` actually exists.
        menuBarController.install()

        // Deferred by one run-loop tick rather than called synchronously — applies whatever was
        // persisted last time (menu-bar-only mode needs the Dock icon hidden again from the first
        // frame, not just when the toggle is flipped), after the rest of this method's AppKit
        // setup has had a chance to settle.
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
                    appDelegate.menuBarController.attach(appState: appState)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
