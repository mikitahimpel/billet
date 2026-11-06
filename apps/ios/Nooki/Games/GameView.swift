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
                            .nookiPrimary()
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
                .font(.nookiHeadline)
                .foregroundStyle(Ink.text)
            if parts.count > 1 {
                Text(parts.dropFirst().joined(separator: ". "))
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.sheet, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
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
