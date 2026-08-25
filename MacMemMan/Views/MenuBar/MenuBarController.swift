import AppKit
import Combine
import SwiftUI

/// Plain-file debug logging for `MenuBarController` — `os_log`/`Logger` output isn't retrievable
/// via `log show`/`log stream` in this particular dev setup (verified: even a definitely-logging
/// system process shows zero lines through that tooling here), so temporary diagnosis goes to a
/// plain file instead, which is unaffected by whatever's blocking the unified log.
private enum MenuBarDebugLog {
    static let url = URL(fileURLWithPath: "/tmp/mmm_debug.log")
    static func write(_ message: String) {
        let line = "\(Date()): \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

/// Hand-rolled `NSStatusItem` + `NSPopover`, replacing SwiftUI's `MenuBarExtra`. In testing here,
/// `MenuBarExtra` would reserve its spot in the menu bar (a real, correctly-sized status item
/// existed) but never actually draw an icon into it — a known reliability gap in that API, not
/// something specific to this app's code. A plain `NSStatusItem.button.image` assignment is the
/// most basic, decades-old AppKit menu bar pattern there is.
@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var cancellable: AnyCancellable?
    private var isInstalled = false

    /// A generous fixed fallback — `MenuBarContentView` declares `.frame(width: 280)` itself; 360
    /// tall covers every row it can show, including the extra "Review Found Items" row that only
    /// appears when a background scan has something pending. Used whenever measuring the real
    /// SwiftUI content's fitting size isn't trustworthy (e.g. before it's ever been laid out).
    private static let fallbackContentSize = NSSize(width: 280, height: 360)

    /// Creates the status item and popover shell. Idempotent — safe to call more than once, and
    /// `attach(appState:)` below defensively calls it too. That matters because this is normally
    /// called from `applicationDidFinishLaunching` while `attach` is called from SwiftUI's
    /// `.onAppear`, two callbacks with NO guaranteed ordering relative to each other. Proven by a
    /// debug build: `.onAppear` fired first at least once, so `attach` ran while `self.popover`
    /// was still nil — its `contentViewController` assignment silently no-op'd on the nil
    /// optional, leaving the *real* popover (created moments later by this method) permanently
    /// content-less. That popover still "shows" on click — as a fully empty, invisible window,
    /// which is indistinguishable from the icon not responding at all.
    func install() {
        guard !isInstalled else { return }
        isInstalled = true

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Without a stable identity, macOS treats every relaunch as registering a brand-new,
        // never-seen-before item — on a menu bar already tight on space (a notch, plus a lot of
        // other apps' own status items), unfamiliar new items are exactly what gets silently
        // pushed into the collapsed/hidden overflow. `autosaveName` gives this item a consistent
        // identity across launches so macOS remembers where the user put it (or that they want it
        // visible) instead of re-litigating that every time.
        item.autosaveName = "com.sanelhadzini.macmemman.statusItem"
        if let button = item.button {
            button.image = Self.icon(isPending: false)
            button.target = self
            button.action = #selector(togglePopover(_:))
            // Explicit, rather than relying on `NSStatusBarButton`'s default mask — this is also
            // what makes a right-click open the same dropdown instead of doing nothing, since a
            // status item has no separate secondary-click behavior unless asked for one.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        MenuBarDebugLog.write("install(): status item created, button=\(item.button != nil)")

        let popover = NSPopover()
        popover.behavior = .transient
        self.popover = popover
    }

    /// Wires up the real dropdown content and the pending-review icon swap — called once
    /// `AppState` exists, from SwiftUI's `.onAppear`. Calls `install()` first (a no-op if it
    /// already ran) so `self.popover` is guaranteed to exist regardless of which of the two
    /// unsynchronized launch callbacks fired first — see `install()`'s comment for why that
    /// matters.
    func attach(appState: AppState) {
        install()

        let content = MenuBarContentView(dismiss: { [weak self] in self?.closePopover() })
            .environmentObject(appState)
        let hosting = NSHostingController(rootView: content)
        popover?.contentViewController = hosting
        // Set AFTER `contentViewController`, not before — assigning a content view controller can
        // reset `NSPopover.contentSize` to that controller's own (unset, effectively zero)
        // `preferredContentSize`, silently undoing a size set beforehand. A zero-size popover
        // "shows" without throwing anything, but is completely invisible — which looks exactly
        // like the icon not responding to clicks at all.
        popover?.contentSize = Self.fallbackContentSize
        MenuBarDebugLog.write("attach(): content view controller set, contentSize=\(String(describing: popover?.contentSize))")

        cancellable = appState.$pendingAutoCleanupManifest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] manifest in
                self?.statusItem?.button?.image = Self.icon(isPending: manifest != nil)
            }
    }

    private static func icon(isPending: Bool) -> NSImage? {
        let name = isPending ? "wind.circle.fill" : "wind"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MacMemMan")
        // Template rendering lets AppKit tint the glyph correctly for light/dark menu bars and
        // selection states automatically.
        image?.isTemplate = true
        return image
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        MenuBarDebugLog.write("togglePopover(): fired, isShown=\(popover?.isShown ?? false)")
        guard let button = statusItem?.button, let popover else {
            MenuBarDebugLog.write("togglePopover(): missing button or popover — statusItem.button=\(statusItem?.button != nil), popover=\(popover != nil)")
            return
        }
        if popover.isShown {
            closePopover()
        } else {
            // Re-measure right before showing — the content's real height varies (an extra row
            // appears when a background scan has something pending). Only trust the measurement
            // if it's a sane, non-degenerate size; otherwise keep the fixed fallback rather than
            // risk collapsing to zero again.
            if let hostingView = popover.contentViewController?.view {
                let fitting = hostingView.fittingSize
                if fitting.width > 100, fitting.height > 20 {
                    popover.contentSize = fitting
                } else {
                    popover.contentSize = Self.fallbackContentSize
                }
            } else {
                popover.contentSize = Self.fallbackContentSize
            }
            MenuBarDebugLog.write("togglePopover(): showing, contentSize=\(popover.contentSize), buttonBounds=\(button.bounds)")
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            addEventMonitor()
            MenuBarDebugLog.write("togglePopover(): after show, isShown=\(popover.isShown), windowFrame=\(String(describing: popover.contentViewController?.view.window?.frame)), windowIsVisible=\(String(describing: popover.contentViewController?.view.window?.isVisible))")
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        removeEventMonitor()
    }

    /// Closes the popover on any click outside it — `.transient` behavior already does this for
    /// clicks on other apps' windows, but not reliably for clicks on other menu bar items, so this
    /// covers the gap explicitly.
    private func addEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }
}
