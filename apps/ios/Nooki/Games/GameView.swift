import FeatureGames
import SwiftUI

/// A mini-game over the room: the whole screen takes the touches for the game, with a glass hint pill and a close
/// button on top, the game's bar and button at the bottom, and its toast once it is done. Nothing else of Home
/// shows meanwhile.
struct GameView: View {
    @State var session: GameSession
    var close: () -> Void
    @State private var touching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
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
                if let hint = session.deck.hint {
                    Text(hint)
                        .font(.nookiCallout)
                        .foregroundStyle(Ink.text)
                        .padding(.horizontal, Space.l)
                        .padding(.vertical, Space.s)
                        .glass(.capsule)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .id(hint)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Spacer(minLength: Space.m)
                Button("Close", systemImage: "xmark", action: end)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.text)
                    .frame(width: 40, height: 40)
                    .glass(.circle, interactive: true)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 60)
            .animation(reduceMotion ? nil : .spring(duration: 0.35), value: session.deck.hint)

            Spacer(minLength: 0)

            if let result = session.finished {
                Toast(result: result, again: session.playAgain, done: end)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack(spacing: Space.m) {
                    if let bar = session.deck.bar {
                        GameBar(value: bar.value, label: bar.label)
                    }
                    if let action = session.action {
                        Button(action: session.act) { Text(action).frame(maxWidth: .infinity) }
                            .nookiPrimary()
                    }
                }
                .padding(.horizontal, Space.gutter)
            }
        }
        .padding(.bottom, 40)
        .animation(reduceMotion ? nil : .spring(duration: 0.45), value: session.finished)
    }

    private func end() {
        session.close(close)
    }
}

/// The bar the game fills, with its label.
private struct GameBar: View {
    let value: Double
    let label: String

    var body: some View {
        HStack(spacing: Space.m) {
            Text(label)
                .font(.nookiCaption)
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
        .glass(.capsule)
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
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
            }
            HStack(spacing: Space.m) {
                Button("Again", action: again)
                    .font(.nookiCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .glass(.capsule, interactive: true)
                Button(action: done) { Text("Done").frame(maxWidth: .infinity) }
                    .nookiPrimary()
            }
        }
        .padding(Space.l)
        .glass(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.horizontal, Space.gutter)
    }
}
