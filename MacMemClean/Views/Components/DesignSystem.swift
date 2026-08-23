import SwiftUI

/// Shared visual language for the app: one signature gradient carried through every screen
/// (sidebar selection, primary buttons, gauges, hero banners) instead of the default macOS blue,
/// bigger/friendlier corner radii, and bold rounded typography — a deliberate, branded look
/// rather than a stack of default SwiftUI/AppKit controls.
enum Design {
    static let cardRadius: CGFloat = 20
    static let rowRadius: CGFloat = 14

    /// The one gradient used everywhere something needs to say "this is the app's identity" —
    /// violet → magenta → amber, used consistently rather than scattered per-screen accents.
    static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.55, green: 0.25, blue: 0.95),
            Color(red: 0.90, green: 0.20, blue: 0.55),
            Color(red: 1.00, green: 0.55, blue: 0.20),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let dangerGradient = LinearGradient(
        colors: [Color(red: 0.95, green: 0.25, blue: 0.35), Color(red: 0.98, green: 0.55, blue: 0.15)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brandGradientVertical = LinearGradient(
        colors: [
            Color(red: 0.55, green: 0.25, blue: 0.95),
            Color(red: 0.90, green: 0.20, blue: 0.55),
            Color(red: 1.00, green: 0.55, blue: 0.20),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static func categoryGradient(_ tint: Color) -> LinearGradient {
        LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct CardBackground: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 20) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// A small colored square icon chip with a vivid diagonal gradient fill and a soft glow — the
/// recurring "badge" motif used in the sidebar, section headers, and card titles.
struct IconChip: View {
    let symbolName: String
    let tint: Color
    var size: CGFloat = 26
    var useBrandGradient: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(useBrandGradient ? Design.brandGradient : Design.categoryGradient(tint))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            )
            .shadow(color: (useBrandGradient ? Color.purple : tint).opacity(0.4), radius: 4, x: 0, y: 2)
    }
}

/// Primary call-to-action button style: bold gradient fill, white rounded-bold text, and a subtle
/// press animation — the branded alternative to the default macOS blue `.borderedProminent`.
struct GradientButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Design.brandGradient
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(controlSize == .large ? .body : .callout, design: .rounded).weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, controlSize == .large ? 20 : 16)
            .padding(.vertical, controlSize == .large ? 12 : 9)
            .background(
                isEnabled ? AnyShapeStyle(gradient) : AnyShapeStyle(Color.secondary.opacity(0.25)),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GradientButtonStyle {
    static var gradient: GradientButtonStyle { GradientButtonStyle() }
    static func gradient(_ gradient: LinearGradient) -> GradientButtonStyle { GradientButtonStyle(gradient: gradient) }
}

/// A hand-drawn spinner, not `ProgressView` — on macOS the indeterminate `ProgressView` style is
/// backed by `NSProgressIndicator` and largely ignores `.tint()`, so it renders as a dark/gray
/// spinner regardless of what color you ask for. That looks broken sitting on a vivid selected
/// row (e.g. white was requested, black showed up). This respects any color exactly.
struct Spinner: View {
    var color: Color = .secondary
    var lineWidth: CGFloat = 2
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0.05, to: 0.85)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear { isSpinning = true }
    }
}
