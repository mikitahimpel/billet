import FeatureGames
import SwiftUI
import Design
import TipKit
import Transport
import WidgetBridge
import Wire

struct WarmBackdrop: View {
    /// Whether the bokeh moves; when it doesn't, it stays where it was.
    var drifts = true
    @Environment(\.scenePhase) private var scenePhase
    /// `-uitestStill YES` holds the bokeh still: redrawn under glass every frame, it keeps the app from ever idling
    /// on CI's GPU-less virtual Macs, and UI queries time out.
    private static let still = UserDefaults.standard.bool(forKey: "uitestStill")
    private var paused: Bool { scenePhase != .active || !drifts || Self.still }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: 0xF4BF7E), Color(hex: 0xB36E3A), Color(hex: 0x4A2C1B), Color(hex: 0x24150D)],
                center: UnitPoint(x: 0.5, y: 0.48),
                startRadius: 10,
                endRadius: 520
            )
            // 10 Hz: the drift is at most 18–24 pt over half a minute, a fraction of a pixel a step, and each step
            // redraws the full screen under the room and its glass.
            TimelineView(.animation(minimumInterval: 1 / 10, paused: paused)) { context in
                Canvas { ctx, size in
                    let t = context.date.timeIntervalSinceReferenceDate
                    for i in 0..<14 {
                        let seed = Double(i) * 12.9898
                        let x = (sin(seed) * 0.5 + 0.5) * size.width + sin(t * 0.15 + seed) * 18
                        let y = (cos(seed * 1.7) * 0.5 + 0.5) * size.height + cos(t * 0.12 + seed) * 24
                        let r = 6 + (sin(seed * 3.1) * 0.5 + 0.5) * 16
                        let alpha = 0.18 + 0.14 * sin(t * 0.6 + seed)
                        // A soft edge `soft` wide on either side of the rim, in place of blurring the whole canvas.
                        let soft = 6.0, outer = r + soft
                        let dot = Gradient(stops: [
                            .init(color: Color(hex: 0xFFD79A, opacity: alpha), location: max(0, r - soft) / outer),
                            .init(color: Color(hex: 0xFFD79A, opacity: 0), location: 1),
                        ])
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - outer, y: y - outer, width: outer * 2, height: outer * 2)),
                            with: .radialGradient(dot, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: outer)
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// The header and the tab bar as the screen's top and bottom bars. On iOS 26 they are safe area bars with the
    /// soft scroll edge under them; before, safe area insets over a material fade when `fades`.
    @ViewBuilder
    func bars(fades: Bool, softEdges: Bool = true, @ViewBuilder top: () -> some View,
              @ViewBuilder bottom: () -> some View) -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .vertical)
                .scrollEdgeEffectHidden(!softEdges, for: .vertical)
                .safeAreaBar(edge: .top, spacing: 12, content: top)
                .safeAreaBar(edge: .bottom, content: bottom)
        } else {
            safeAreaInset(edge: .top, spacing: 12) {
                top().background { if fades { EdgeFade(edge: .top) } }
            }
            .safeAreaInset(edge: .bottom) {
                bottom().background { if fades { EdgeFade(edge: .bottom) } }
            }
        }
    }
}

/// Below iOS 26: material that fades out away from the screen edge, under a bar and through the status bar or the
/// home indicator, so scrolled content softens instead of ending at a line.
private struct EdgeFade: View {
    let edge: VerticalEdge

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(LinearGradient(colors: [.black, .black, .clear],
                                 startPoint: edge == .top ? .top : .bottom,
                                 endPoint: edge == .top ? .bottom : .top))
            .padding(edge == .top ? .bottom : .top, -20)
            .ignoresSafeArea(edges: edge == .top ? .top : .bottom)
            .allowsHitTesting(false)
    }
}
