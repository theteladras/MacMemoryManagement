import SwiftUI

/// A soft, slowly drifting blurred-gradient backdrop — the Instagram/iOS "aurora" look, built
/// from the app's own brand palette (see `Design.brandGradient`) so it reinforces identity rather
/// than competing with content. Sits behind the sidebar and main content, both of which use a
/// translucent material, so this shows through as a gentle tint rather than a loud background.
///
/// Capped to 30fps (not a full-rate `TimelineView`) and rendered via `Canvas` + `.drawingGroup()`
/// (Metal-backed compositing) since this runs continuously, behind everything, in an app that's
/// otherwise CPU-light — a naive per-frame `ZStack` of blurred circles would be far more expensive
/// for the same visual result.
struct AnimatedGradientBackground: View {
    private struct Blob {
        let baseX: CGFloat // fraction of width, 0...1
        let baseY: CGFloat // fraction of height, 0...1
        let radius: CGFloat
        let color: Color
        let speed: Double
        let phase: Double
    }

    // Kept away from the very top edge on purpose: the native window title bar (traffic lights,
    // "Overview" label) is opaque AppKit chrome this view can't draw behind or unify with, so a
    // blob anchored near y=0 read as a hard, ugly seam right under it instead of a soft blend.
    // Centering the vertical range instead lets the material's own blur do the transition softly.
    private let blobs: [Blob] = [
        Blob(baseX: 0.12, baseY: 0.32, radius: 260, color: Color(red: 0.55, green: 0.25, blue: 0.95), speed: 0.05, phase: 0.0),
        Blob(baseX: 0.88, baseY: 0.28, radius: 300, color: Color(red: 0.90, green: 0.20, blue: 0.55), speed: 0.045, phase: 2.1),
        Blob(baseX: 0.78, baseY: 0.80, radius: 320, color: Color(red: 1.00, green: 0.55, blue: 0.20), speed: 0.04, phase: 4.2),
        Blob(baseX: 0.18, baseY: 0.76, radius: 240, color: Color(red: 0.35, green: 0.35, blue: 0.95), speed: 0.055, phase: 1.4),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            Canvas { canvasContext, size in
                let t = context.date.timeIntervalSinceReferenceDate
                for blob in blobs {
                    let angle = t * blob.speed + blob.phase
                    let driftX = CGFloat(cos(angle)) * 0.07
                    let driftY = CGFloat(sin(angle * 1.3)) * 0.07
                    let center = CGPoint(
                        x: (blob.baseX + driftX) * size.width,
                        y: (blob.baseY + driftY) * size.height
                    )
                    let rect = CGRect(x: center.x - blob.radius, y: center.y - blob.radius, width: blob.radius * 2, height: blob.radius * 2)
                    let gradient = Gradient(colors: [blob.color.opacity(0.38), blob.color.opacity(0)])
                    canvasContext.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: blob.radius)
                    )
                }
            }
            .blur(radius: 70)
        }
        .drawingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
