import OurioShared
import SwiftUI
import Design
import TipKit

/// A hint is a card: the same surface, type and icon tile as every card in the app, in the theme the app is in. Its
/// popover's arrow points at the control it is about, and that control is ringed (`hint(_:arrowEdge:target:)`).
struct HintStyle: TipViewStyle {
    let hints: Hints

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            configuration.image?
                .font(.ourioHeadline)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Ink.accentText)
                .frame(width: Size.cardMark, height: Size.cardMark)
                .background(Color.honey.opacity(0.16), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.xs) {
                configuration.title?
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                configuration.message?
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.textSecondary)
                ForEach(configuration.actions) { action in
                    Button(action: action.handler) { action.label() }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                        .padding(.top, Space.xs)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                hints.close(configuration.tip)
            } label: {
                Image(systemName: "xmark")
                    .font(.ourioCaption.weight(.bold))
                    .foregroundStyle(Ink.textSecondary)
                    .frame(width: Size.control, height: Size.control)
                    .contentShape(.rect)
            }
            .buttonStyle(PressScaleStyle())
            // The tap area reaches into the card's padding, so the glyph lines up with the title.
            .padding([.top, .trailing], -Space.m)
            .accessibilityLabel("Close hint")
        }
        .padding(CardMetrics.padding)
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
                if showing {
                    target
                        .strokeBorder(Color.honey, lineWidth: 2.5)
                        .padding(-Space.xs)
                        .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.35]) { ring, opacity in
                            ring.opacity(opacity)
                        } animation: { _ in Motion.fade(Motion.standard) }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .animation(Motion.fade(), value: showing)
            .task {
                for await shows in tip.shouldDisplayUpdates { showing = shows }
            }
    }
}
