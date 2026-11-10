import OurioShared
import SwiftUI
import Design
import TipKit

/// TipKit's look for every hint: the design package's `Callout` card in the app's theme. Its popover's arrow points
/// at the control it is about, and that control is ringed (`hint(_:arrowEdge:target:)`).
struct HintStyle: TipViewStyle {
    let hints: Hints

    func makeBody(configuration: Configuration) -> some View {
        Callout(close: { hints.close(configuration.tip) }) {
            configuration.image
        } title: {
            configuration.title
        } message: {
            configuration.message
        } actions: {
            ForEach(configuration.actions) { action in
                CalloutButton(action: action.handler) { action.label() }
            }
        }
        .onAppear { hints.appeared(configuration.tip) }
    }
}

extension View {
    func hintStyle(_ hints: Hints) -> some View {
        tipViewStyle(HintStyle(hints: hints))
            .tipBackground(Ink.surface)
    }

    /// The hint's popover, with its arrow at this view, and a honey ring around `target` while it shows.
    func hint<T: HintTip>(_ tip: T, arrowEdge: Edge, target: some InsettableShape) -> some View {
        modifier(HintRing(tip: tip, target: target)).popoverTip(tip, arrowEdge: arrowEdge)
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
                        target
                            .strokeBorder(Color.honey, lineWidth: 2.5)
                            .padding(-Space.xs)
                            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.35]) { ring, opacity in
                                ring.opacity(opacity)
                            } animation: { _ in Motion.fade(Motion.standard) }
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
