import FeatureGames
import GamesInterface
import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import UsInterface

/// A mini-game over the room: the whole screen takes the touches for the game, with a glass hint pill and a close
/// button on top, the game's bar and button at the bottom, and its toast once it is done. Nothing else of Home
/// shows meanwhile.
struct GameView: View {
    @State var session: GameSession
    var scenes: GameSceneSwitch
    var close: () -> Void
    @State private var touching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The hint and the bar sit over the game: past this they would cover the thing to touch.
    static let overlayType = DynamicTypeSize.xxxLarge

    var body: some View {
        GeometryReader { proxy in
            let full = proxy.size
            ZStack {
                Color.clear
                    .ignoresSafeArea()
                    // The touch layer's own size is the screen's: a touch and a ray into the room share its space.
                    .onGeometryChange(for: CGSize.self, of: \.size) { session.resize($0) }
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
                                if GameExit.isSwipe(from: value.startLocation, translation: value.translation) { end() }
                            }
                    )
                    .accessibilityHidden(true)

                if let pointer = session.pointer {
                    CueHand(pointer: pointer)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                controls
            }
            .onAppear { session.start(viewport: full) }
        }
    }

    private var controls: some View {
        VStack(spacing: Space.m) {
            HStack(spacing: Space.s) {
                GameTitle(game: session.game)
                if scenes.options.count > 1 { SceneMenu(scenes: scenes, select: move) }
                Spacer(minLength: 0)
                // The glass sits behind the label and takes no touch itself: over the RealityKit room a glass view
                // on the Button swallows the tap.
                Button("Close", systemImage: "xmark", action: end)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.ourioHeadline)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(Ink.glassGlyph)
                    .frame(width: Size.control, height: Size.control)
                    .contentShape(.circle)
                    .background { Color.clear.glass(.circle, role: .control).allowsHitTesting(false) }
            }
            .padding(.horizontal, Space.gutter)

            Spacer(minLength: 0)

            if let result = session.finished {
                ResultToast(result: result, again: session.playAgain, done: end)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack(spacing: Space.m) {
                    if let hint = session.shownHint {
                        GoalHint(text: hint)
                            .dynamicTypeSize(...Self.overlayType)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id(hint)
                    }
                    if let bar = session.deck.bar {
                        GameBar(meter: bar, symbol: session.game.symbol)
                            .dynamicTypeSize(...Self.overlayType)
                    }
                    if let action = session.action {
                        Button(action: session.act) { Text(action).frame(maxWidth: .infinity) }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    if let assist = session.assist {
                        Button(action: session.assistAct) { Text(assist).frame(maxWidth: .infinity) }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityHint("Wipes up the puddle for you")
                    }
                }
                .padding(.horizontal, Space.gutter)
            }
        }
        .padding(.top, Space.s)
        .padding(.bottom, Space.l)
        .animation(reduceMotion ? nil : .spring(duration: 0.45), value: session.finished)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: session.shownHint)
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
    @State private var arrived = false

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
        .opacity(arrived ? 1 : 0)
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.easeOut(duration: 0.25)) { arrived = true }
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

/// The game's one goal, in words: a line of glass over the scene, gone at the first touch and back only to correct.
private struct GoalHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ourioHeadline)
            .foregroundStyle(Ink.glassGlyph)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .glass(.capsule, role: .bar)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Which game this is, at a glance: its icon and short name. The name goes at accessibility sizes, the icon stays.
private struct GameTitle: View {
    let game: MiniGame
    @Environment(\.dynamicTypeSize) private var type

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: game.symbol).dynamicTypeSize(...GameView.overlayType)
            if !type.isAccessibilitySize { Text(game.shortTitle) }
        }
        .font(.ourioHeadline)
        .foregroundStyle(Ink.glassGlyph)
        .padding(.horizontal, Space.m)
        .frame(minHeight: Size.control)
        .glass(.capsule, role: .bar)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.shortTitle)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Where it is played, always visible, and the other places one tap away.
private struct SceneMenu: View {
    let scenes: GameSceneSwitch
    var select: (GameScenery) -> Void

    var body: some View {
        Menu {
            ForEach(scenes.options, id: \.self) { scene in
                Button { select(scene) } label: {
                    Label(scene.title, systemImage: scene == scenes.selected ? "checkmark" : scene.symbol)
                }
            }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: scenes.selected.symbol)
                Text(scenes.selected.title)
                Image(systemName: "chevron.down").font(.ourioMicro)
            }
            .font(.ourioHeadline)
            .foregroundStyle(Ink.glassGlyph)
            .padding(.horizontal, Space.m)
            .frame(minHeight: Size.control)
            .background { Color.clear.glass(.capsule, role: .bar).allowsHitTesting(false) }
            .contentShape(.capsule)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityIdentifier("gameScene")
        .accessibilityLabel("Scene")
        .accessibilityValue(scenes.selected.title)
    }
}

/// How far along: an icon, what is filling, the count, and a thick honey meter on a dark glass track.
private struct GameBar: View {
    let meter: GameMeter
    let symbol: String
    @Environment(\.dynamicTypeSize) private var type

    private var percent: Int { Int((meter.value * 100).rounded()) }

    var body: some View {
        let layout = type.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s))
            : AnyLayout(HStackLayout(spacing: Space.m))
        layout {
            HStack(spacing: Space.s) {
                Image(systemName: symbol)
                Text(meter.label)
                if type.isAccessibilitySize { Spacer(minLength: Space.s); value }
            }
            .lineLimit(1)
            track
            if !type.isAccessibilitySize { value }
        }
        .font(.ourioHeadline)
        .foregroundStyle(Ink.glassGlyph)
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .glass(.capsule, role: .bar)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meter.label)
        .accessibilityValue(meter.detail ?? "\(percent) percent")
    }

    private var value: some View {
        Text(meter.detail ?? "\(percent)%")
            .font(.ourioHeadline)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private var track: some View {
        Capsule()
            .fill(Ink.glassGlyphSecondary.opacity(0.35))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.honeyGradient)
                        .frame(width: max(proxy.size.height, proxy.size.width * min(max(meter.value, 0), 1)))
                }
            }
            .frame(height: Space.m)
            .frame(minWidth: Size.control)
    }
}

/// The finished game: what she got, and either another round or back to the room.
private struct ResultToast: View {
    let result: GameResult
    var again: () -> Void
    var done: () -> Void

    var body: some View {
        Toast {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(result.line(pronouns: CatProfile.pronouns()))
                    .font(.ourioTitle)
                    .foregroundStyle(Ink.text)
                HStack(spacing: Space.s) {
                    Chip(result.game.careLabel(grams: result.grams), symbol: result.game.symbol, style: .quiet)
                    Chip("Coins", coinStyle: .quiet)
                }
                buttons
            }
        }
        .padding(.horizontal, Space.gutter)
    }

    /// Side by side at one width and height while both fit, else stacked full width, the main one last as in `Screen`.
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            EqualRow(spacing: Space.s) {
                SecondaryButton("Play again", action: again).lineLimit(1)
                PrimaryButton("Back to the room", action: done).lineLimit(1)
            }
            VStack(spacing: Space.s) {
                SecondaryButton("Play again", action: again)
                PrimaryButton("Back to the room", action: done)
            }
        }
    }
}

/// A row whose items share the width of the widest one, so it reports a width that holds every label in full:
/// an `HStack` of full-width buttons reports the sum of their own widths, and the equal split then cuts the longer.
private struct EqualRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let widest = sizes.map(\.width).max() ?? 0
        let width = widest * CGFloat(subviews.count) + spacing * CGFloat(max(subviews.count - 1, 0))
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 0
        return CGSize(width: max(width, offered), height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let each = (bounds.width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            let x = bounds.minX + (each + spacing) * CGFloat(index)
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: each, height: bounds.height))
        }
    }
}

extension MiniGame {
    fileprivate var symbol: String {
        switch self {
        case .feed: "fork.knife"
        case .water: "drop.fill"
        case .laser: "tennisball.fill"
        case .brush: "paintbrush.fill"
        }
    }

    fileprivate var shortTitle: String {
        switch self {
        case .feed: "Feed"
        case .water: "Water"
        case .laser: "Play"
        case .brush: "Brush"
        }
    }

    fileprivate func careLabel(grams: Int?) -> String {
        switch self {
        case .feed: grams.map { "Fed \($0) g" } ?? "Fed"
        case .water: "Fresh water"
        case .laser: "Played"
        case .brush: "Brushed"
        }
    }
}

extension GameScenery {
    fileprivate var symbol: String {
        switch self {
        case .room: "house.fill"
        case .rug: "square.grid.2x2.fill"
        case .kitchen: "fork.knife"
        }
    }
}
