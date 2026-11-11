import Design
import SwiftUI

/// The first screen: Mochi alive in the warm room, and one clay card under her with the line, what the app is for
/// in three rows and the terms as its footnote. The actions sit under it, in `OnboardingView.actions`. The stage takes
/// whatever height the card leaves it; when that is too little (an SE, large text), the page scrolls with the
/// smallest stage. The timeline in `WelcomeScript` only changes opacity, scale and offset, so nothing moves the
/// layout while it plays.
struct WelcomeView: View {
    let start: Date
    var coat = CatCoat.grey
    var script = WelcomeScript.standard
    var waved: () -> Void = {}
    var probe: HitchProbe?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Seconds after `start` of the last tap on her.
    @State private var pokedAt: TimeInterval?

    /// The stage's bounds, in points: under the smallest she is too small to read as a cat (an SE at the default text
    /// size leaves about this much), past the largest she crowds the words on a Pro Max.
    static let stageHeights: ClosedRange<CGFloat> = 120...380

    private static let points: [(symbol: String, text: LocalizedStringKey)] = [
        ("pawprint.fill", "Feed it, pet it and play with it together"),
        ("scribble.variable", "Send each other drawings and notes"),
        ("flame.fill", "Keep a streak going, day after day"),
    ]

    var body: some View {
        // The fit is decided once, outside the clock: the script never changes a size.
        ViewThatFits(in: .vertical) {
            playing(stage: nil)
            ScrollView { playing(stage: Self.stageHeights.lowerBound) }
                .softScrollEdges()
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityElement(children: .contain)
    }

    private func playing(stage: CGFloat?) -> some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = reduceMotion ? script.duration : context.date.timeIntervalSince(start)
            zones(time: time, stage: stage)
                // Only while the script plays: the frames after it are the UI test's, reading the probe.
                .onChange(of: context.date) {
                    if time <= script.duration { probe?.frame(context.date) } else { probe?.finish() }
                }
        }
    }

    /// `stage` nil: the stage grows into the height left over, within `stageHeights`.
    private func zones(time: TimeInterval, stage: CGFloat?) -> some View {
        VStack(spacing: Space.m) {
            CatHeroStage(coat: coat, time: time, pokedAt: pokedAt, moving: !reduceMotion)
                .frame(minHeight: stage ?? Self.stageHeights.lowerBound,
                       maxHeight: stage ?? Self.stageHeights.upperBound)
                .layoutPriority(-1)
                .contentShape(.rect)
                .onTapGesture {
                    pokedAt = Date.now.timeIntervalSince(start)
                    waved()
                }
                .modifier(Reveal(script.progress(.cat, at: time), rise: 12))
            card(time: time)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.m)
    }

    private func card(time: TimeInterval) -> some View {
        Card(warm: true) {
            VStack(spacing: Space.m) {
                Text("A cat for the two of you")
                    .font(.ourioLargeTitle)
                    .foregroundStyle(Ink.text)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .modifier(SpringIn(script.spring(.title, at: time)))
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(Self.points.indices, id: \.self) { index in
                        Point(symbol: Self.points[index].symbol, text: Self.points[index].text)
                            .modifier(Reveal(script.progress(.vignette(index), at: time), rise: 10))
                    }
                }
                Hairline()
                // Both welcome actions accept these (OnboardingFlow.termsAcceptedKey). App Review 1.2 asks for terms that
                // forbid objectionable content before anyone can send any.
                Text("""
                    By continuing you agree to the terms of use: no abusive or objectionable content, and every \
                    report is acted on.
                    """)
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("welcome.terms")
                    .modifier(Reveal(script.progress(.subtitle, at: time), rise: 0))
            }
        }
        .modifier(Reveal(script.progress(.title, at: time), rise: 14))
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

/// One thing the app is for: its symbol in the card's icon wash, then the words.
private struct Point: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: Space.m) {
            RowIcon(symbol: symbol, size: Size.cardMark)
            Text(text)
                .font(.ourioBody)
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
