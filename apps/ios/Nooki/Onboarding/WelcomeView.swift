import Design
import SwiftUI

/// The first screen: Mochi alive on a warm stage, one line, three small vignettes, then the actions below. Every part
/// has a fixed box sized from the screen, and the timeline in `WelcomeScript` only changes opacity, scale and offset
/// inside those boxes, so nothing moves the layout while it plays.
struct WelcomeView: View {
    let start: Date
    var coat = CatCoat.grey
    var script = WelcomeScript.standard
    var waved: () -> Void = {}
    var probe: HitchProbe?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Seconds after `start` of the last tap on her.
    @State private var pokedAt: TimeInterval?

    private static let points: [(symbol: String, text: LocalizedStringKey)] = [
        ("pawprint.fill", "Feed it, pet it and play with it together"),
        ("scribble.variable", "Send each other drawings and notes"),
        ("flame.fill", "Keep a streak going, day after day"),
    ]

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: reduceMotion)) { context in
                let time = reduceMotion ? script.duration : context.date.timeIntervalSince(start)
                content(proxy.size, time: time)
                    // Only while the script plays: the frames after it are the UI test's, reading the probe.
                    .onChange(of: context.date) {
                        if time <= script.duration { probe?.frame(context.date) } else { probe?.finish() }
                    }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func content(_ size: CGSize, time: TimeInterval) -> some View {
        let catHeight = min(size.height * 0.42, 360)
        return VStack(spacing: 0) {
            CatHeroStage(coat: coat, time: time, pokedAt: pokedAt, moving: !reduceMotion)
                .frame(height: catHeight)
                .contentShape(.rect)
                .onTapGesture {
                    pokedAt = Date.now.timeIntervalSince(start)
                    waved()
                }
                .modifier(Reveal(script.progress(.cat, at: time), rise: 12))
                .padding(.bottom, Space.l)
            Text("A cat for the two of you")
                .font(.ourioLargeTitle)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .modifier(SpringIn(script.spring(.title, at: time)))
                .accessibilityAddTraits(.isHeader)
            Text("Feed it, play with it and keep each other close.")
                .font(.ourioBody)
                .foregroundStyle(Ink.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s)
                .modifier(Reveal(script.progress(.subtitle, at: time), rise: 8))
            Spacer(minLength: Space.l)
            HStack(alignment: .top, spacing: Space.m) {
                ForEach(Self.points.indices, id: \.self) { index in
                    Vignette(symbol: Self.points[index].symbol, text: Self.points[index].text, time: time)
                        .modifier(Reveal(script.progress(.vignette(index), at: time), rise: 14))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, Space.m)
            // Both actions below accept this (OnboardingFlow.termsAcceptedKey). App Review 1.2 asks for terms that
            // forbid objectionable content before anyone can send any.
            Text("""
                By continuing you agree to the terms of use: no abusive or objectionable content, and every \
                report is acted on.
                """)
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, Space.s)
                .modifier(Reveal(script.progress(.subtitle, at: time), rise: 0))
        }
        .padding(.horizontal, Space.gutter)
        .frame(width: size.width, height: size.height)
    }
}

/// Opacity and a small rise, from one number. Opacity and offset never change a view's layout.
private struct Reveal: ViewModifier {
    let progress: Double
    let rise: CGFloat

    init(_ progress: Double, rise: CGFloat) {
        self.progress = progress
        self.rise = rise
    }

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: rise * (1 - progress))
    }
}

/// Comes in on a spring with no overshoot: it fades in quickly, rises and grows to its size as the spring settles.
private struct SpringIn: ViewModifier {
    let progress: Double

    init(_ progress: Double) { self.progress = progress }

    func body(content: Content) -> some View {
        content
            .opacity(min(progress * 1.6, 1))
            .scaleEffect(0.9 + 0.1 * progress)
            .offset(y: 18 * (1 - progress))
    }
}

/// A benefit as a small animated tile: its symbol breathes, driven by the same clock as the script.
private struct Vignette: View {
    let symbol: String
    let text: LocalizedStringKey
    let time: TimeInterval

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Ink.accentText)
                .scaleEffect(1 + 0.08 * sin(time * 2.4))
                .frame(width: Size.control, height: Size.control)
                .background(Color.honey.opacity(0.18), in: .circle)
            Text(text)
                .font(.ourioCaption)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .top)
        .padding(.vertical, Space.m)
        .padding(.horizontal, Space.s)
        .background(Ink.surface, in: .rect(cornerRadius: Radius.card))
    }
}
