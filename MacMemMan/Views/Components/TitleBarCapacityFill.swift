import AppKit
import SwiftUI

/// Grabs a reference to the hosting `NSWindow` so SwiftUI can set window-chrome properties that
/// have no SwiftUI-native API — here, `titlebarAppearsTransparent`, the standard "unified toolbar"
/// recipe (Xcode, Mail, Music, etc. all use it) that lets our own content show through the title
/// bar strip instead of it staying a flat, separate bar. Traffic lights, the title text, and
/// window dragging all keep working exactly as before — only the title bar's own background paint
/// becomes see-through.
final class WindowConfiguratorView: NSView {
    var configure: (NSWindow) -> Void = { _ in }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            configure(window)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowConfiguratorView {
        let view = WindowConfiguratorView()
        view.configure = configure
        return view
    }

    func updateNSView(_ nsView: WindowConfiguratorView, context: Context) {
        nsView.configure = configure
    }
}

/// A capacity-bar fill drawn *into* the title bar strip — the brand gradient fills left-to-right in
/// proportion to how full the disk is, so the very top of the window doubles as an at-a-glance
/// usage indicator. Never intercepts clicks (`allowsHitTesting(false)`), so window dragging and the
/// traffic lights/toolbar button above it are completely unaffected.
struct TitleBarCapacityFill: View {
    let fraction: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Design.brandGradient
                .frame(width: max(0, geometry.size.width * min(max(fraction, 0), 1)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(0.55)
        }
        .frame(height: height)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}
