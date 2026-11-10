import FeatureGames
import GamesInterface
import OurioShared
import SwiftUI
import Design

/// A mini-game over the room: the whole screen takes the touches for the game, with a glass hint pill and a close
/// button on top, the game's bar and button at the bottom, and its toast once it is done. Nothing else of Home
/// shows meanwhile.
struct GameView: View {
    @State var session: GameSession
    /// The corner the game is played in, or nil for the room itself.
    var corner: TabletopRoom?
    var scenes: GameSceneSwitch
    var close: () -> Void
    @State private var touching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let corner { TabletopView(room: corner) }
                Color.clear
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                session.touch(touching ? .moved : .began, at: value.location)
                                touching = true
                            }
                            .onEnded { value in
                                touching = false
                                session.touch(.ended, at: value.location)
                                // A swipe down from the top edge leaves, where the stages' own drags never start.
                                let drag = value.translation
                                if value.startLocation.y < 140, drag.height > 90, abs(drag.width) < drag.height {
                                    end()
                                }
                            }
                    )
                    .accessibilityHidden(true)

                if let pointer = session.pointer {
                    CueHand(pointer: pointer)
                        .transition(.opacity)
                }

                controls
            }
            .onAppear { session.start(viewport: proxy.size) }
            .onChange(of: proxy.size) { _, size in session.resize(size) }
        }
        .ignoresSafeArea()
    }

    private var controls: some View {
        VStack(spacing: Space.m) {
            HStack(alignment: .top) {
                GlassSegmented(
                    scenes.options.map { ($0, $0.title) },
                    selection: Binding(get: { scenes.selected }, set: { move(to: $0) }),
                    identifier: "gameScene"
                )
                .accessibilityLabel("Scene")
                .accessibilityValue(scenes.selected.title)
                Spacer(minLength: Space.m)
                // The glass sits behind the label and takes no touch itself: over the RealityKit room a glass view
                // on the Button swallows the tap.
                Button("Close", systemImage: "xmark", action: end)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .ourioScaledFont(size: 15, weight: .semibold)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(Ink.glassGlyph)
                    .frame(width: Size.control, height: Size.control)
                    .contentShape(.circle)
                    .background { Color.clear.glass(.circle, role: .bar).allowsHitTesting(false) }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 60)

            Spacer(minLength: 0)

            if let result = session.finished {
                ResultToast(result: result, again: session.playAgain, done: end)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack(spacing: Space.m) {
                    if let hint = session.deck.hint {
                        HintCard(text: hint)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id(hint)
                    }
                    if let bar = session.deck.bar {
                        GameBar(value: bar.value, label: bar.label)
                    }
                    if let action = session.action {
                        Button(action: session.act) { Text(action).frame(maxWidth: .infinity) }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(.horizontal, Space.gutter)
            }
        }
        .padding(.bottom, 40)
        .animation(reduceMotion ? nil : .spring(duration: 0.45), value: session.finished)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: session.deck.hint)
        .animation(.easeInOut(duration: 0.2), value: session.pointer == nil)
    }

    /// Between two corners the game carries on; to or from the room it is closed here and starts over there.
    private func move(to next: GameScenery) {
        guard next != scenes.selected else { return }
        if next.isCorner == scenes.selected.isCorner {
            scenes.select(next)
        } else {
            session.close(now: true) { scenes.select(next) }
        }
    }

    private func end() {
        session.close(close)
    }
}

/// The scenes a game can be played in, and the one it is in: a single control, the game's own Room | City.
struct GameSceneSwitch {
    let options: [GameScenery]
    let selected: GameScenery
    var select: (GameScenery) -> Void
}

/// The hint hand over the thing to touch: a honey ring on it, and a hand that taps it, presses and holds it, rubs it
/// or drags from it to where it should go, again and again until the first touch.
private struct CueHand: View {
    let pointer: GamePointer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = reduceMotion
        ZStack {
            Circle()
                .stroke(Color.honey, lineWidth: 3)
                .frame(width: Size.control, height: Size.control)
                .phaseAnimator([false, true]) { ring, big in
                    ring.scaleEffect(still ? 1 : big ? 1.25 : 0.9).opacity(big ? 0.55 : 1)
                } animation: { _ in .easeInOut(duration: 0.8) }
                .position(pointer.from)
            if let to = pointer.to {
                Path { path in
                    path.move(to: pointer.from)
                    path.addLine(to: to)
                }
                .stroke(Color.honey.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 9]))
            }
            hand
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Sits down and to the right of the point, as a finger on it would.
    private var hand: some View {
        let from = pointer.from
        let to = pointer.to ?? pointer.from
        let offset = CGSize(width: Size.control * 0.35, height: Size.control * 0.45)
        return Image(systemName: "hand.point.up.left.fill")
            .ourioScaledFont(size: 22, weight: .semibold)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(Ink.glassGlyph)
            .frame(width: Size.control, height: Size.control)
            .glass(.circle, role: .bar)
            .keyframeAnimator(initialValue: HandMotion(), repeating: !reduceMotion) { view, motion in
                view
                    .scaleEffect(motion.press)
                    .position(x: from.x + (to.x - from.x) * motion.along + offset.width + motion.rub,
                              y: from.y + (to.y - from.y) * motion.along + offset.height)
            } keyframes: { _ in
                motion
            }
    }

    /// One loop of the hand: a press (held for `hold`), a slide along the drag's path, a rub to and fro.
    @KeyframesBuilder<HandMotion>
    private var motion: some Keyframes<HandMotion> {
        let gesture = pointer.gesture
        let press: (wait: Double, depth: CGFloat, hold: Double, lift: Double) = switch gesture {
        case .tap: (0.5, 0.82, 0.01, 0.45)
        case .hold: (0.4, 0.82, 1.2, 0.4)
        case .rub, .drag: (0.01, 0.86, 1.5, 0.5)
        }
        let along: CGFloat = gesture == .drag ? 1 : 0
        let rub: CGFloat = gesture == .rub ? 14 : 0
        KeyframeTrack(\HandMotion.press) {
            CubicKeyframe(1, duration: press.wait)
            SpringKeyframe(press.depth, duration: 0.2)
            LinearKeyframe(press.depth, duration: press.hold)
            SpringKeyframe(1, duration: press.lift)
        }
        KeyframeTrack(\HandMotion.along) {
            LinearKeyframe(0, duration: 0.3)
            CubicKeyframe(along, duration: 1.2)
            LinearKeyframe(along, duration: 0.5)
        }
        KeyframeTrack(\HandMotion.rub) {
            LinearKeyframe(0, duration: 0.3)
            CubicKeyframe(-rub, duration: 0.3)
            CubicKeyframe(rub, duration: 0.3)
            CubicKeyframe(-rub, duration: 0.3)
            CubicKeyframe(0, duration: 0.3)
            LinearKeyframe(0, duration: 0.5)
        }
    }
}

private struct HandMotion {
    var press: CGFloat = 1
    var along: CGFloat = 0
    var rub: CGFloat = 0
}

/// What to do next, above the play area on a solid card: the first sentence as the line, the rest under it.
private struct HintCard: View {
    let text: String

    var body: some View {
        let parts = text.components(separatedBy: ". ")
        VStack(alignment: .leading, spacing: 2) {
            Text(parts[0])
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
            if parts.count > 1 {
                Text(parts.dropFirst().joined(separator: ". "))
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cornerFill(.card, Ink.screen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct GameBar: View {
    let value: Double
    let label: String

    var body: some View {
        HStack(spacing: Space.m) {
            Text(label)
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
            Capsule()
                .fill(Ink.surface.opacity(0.6))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.honeyGradient)
                            .frame(width: max(proxy.size.height, proxy.size.width * min(max(value, 0), 1)))
                    }
                }
                .frame(height: 10)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .glass(.capsule, role: .bar)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

/// The finished game: what she got, and either another round or back to the room.
private struct ResultToast: View {
    let result: GameResult
    var again: () -> Void
    var done: () -> Void

    var body: some View {
        Toast {
            VStack(spacing: Space.m) {
                HStack(spacing: Space.s) {
                    CoinIcon(size: 18)
                    Text(result.line)
                        .font(.ourioHeadline)
                        .foregroundStyle(Ink.text)
                }
                ActionRow {
                    SecondaryButton("Again", action: again)
                    PrimaryButton("Done", action: done)
                }
            }
        }
        .padding(.horizontal, Space.gutter)
    }
}
