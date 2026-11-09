import FeatureGames
import GamesInterface
import SwiftUI
import Design

/// A mini-game over the room: the whole screen takes the touches for the game, with a glass hint pill and a close
/// button on top, the game's bar and button at the bottom, and its toast once it is done. Nothing else of Home
/// shows meanwhile.
struct GameView: View {
    @State var session: GameSession
    /// The corner the game is played in, or nil for the room itself.
    var corner: TabletopRoom?
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
                Spacer(minLength: Space.m)
                // The glass sits behind the label and takes no touch itself: over the RealityKit room a glass view
                // on the Button swallows the tap.
                Button("Close", systemImage: "xmark", action: end)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.glassGlyph)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
                    .background { Color.clear.glass(.circle, role: .bar).allowsHitTesting(false) }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 60)

            Spacer(minLength: 0)

            if let result = session.finished {
                Toast(result: result, again: session.playAgain, done: end)
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
    }

    private func end() {
        session.close(close)
    }
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
        .background(Ink.screen, in: .rect(cornerRadius: Radius.card, style: .continuous))
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
private struct Toast: View {
    let result: GameResult
    var again: () -> Void
    var done: () -> Void

    var body: some View {
        VStack(spacing: Space.m) {
            HStack(spacing: Space.s) {
                CoinIcon(size: 18)
                Text(result.line)
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
            }
            HStack(spacing: Space.m) {
                Button("Again", action: again)
                    .font(.ourioCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .glass(.capsule, interactive: true)
                Button(action: done) { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Space.l)
        .glass(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.horizontal, Space.gutter)
    }
}
