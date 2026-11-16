import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import TipKit
import UsInterface

extension View {
    /// The hint's card, drawn by `HintLayer` with its arrow at this view, and a honey ring around `target` while it
    /// shows. `arrowEdge` is the card's edge the arrow is on: `.bottom` puts the card above the view.
    func hint<T: HintTip>(_ tip: T, arrowEdge: Edge, target: some InsettableShape) -> some View {
        modifier(HintRing(tip: tip, target: target)).modifier(HintAnchor(id: T.hintId, edge: arrowEdge))
    }
}

/// Tells `Hints` where its view is, for the card that points at it.
private struct HintAnchor: ViewModifier {
    let id: String
    let edge: Edge
    @Environment(Hints.self) private var hints

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                hints.place(id, HintSpot(frame: frame, edge: edge))
            }
            .onDisappear { hints.place(id, nil) }
    }
}

private struct HintRing<T: HintTip, Target: InsettableShape>: ViewModifier {
    let tip: T
    let target: Target
    @State private var showing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if showing {
                        // A few pulses, then it holds: a ring that pulses for as long as the hint waits keeps
                        // the header's glass redrawing every frame.
                        target
                            .strokeBorder(Color.honey, lineWidth: 2.5)
                            .padding(-Space.xs)
                            .keyframeAnimator(initialValue: 1.0, repeating: false) { ring, opacity in
                                ring.opacity(reduceMotion ? 1 : opacity)
                            } keyframes: { _ in
                                CubicKeyframe(0.35, duration: Motion.standard)
                                CubicKeyframe(1, duration: Motion.standard)
                                CubicKeyframe(0.35, duration: Motion.standard)
                                CubicKeyframe(1, duration: Motion.standard)
                                CubicKeyframe(0.35, duration: Motion.standard)
                                CubicKeyframe(1, duration: Motion.standard)
                            }
                            .transition(.opacity)
                    }
                }
                // Hidden as a whole, and animated from the task rather than by `.animation` on the control: inside
                // the header's glass container either made iOS 27 report the container's merged frame for the
                // Inbox (`TabBarTouchTests`).
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            .task {
                for await shows in tip.shouldDisplayUpdates {
                    withAnimation(Motion.fade()) { showing = shows }
                }
            }
    }
}
