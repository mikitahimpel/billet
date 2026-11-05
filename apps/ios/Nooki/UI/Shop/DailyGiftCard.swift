import SwiftUI

/// The free gift at the top of Today: one tap opens it with a little burst, and it comes back at local midnight.
struct DailyGiftCard: View {
    let state: HomeState

    @State private var reward: GiftReward?
    @State private var bursts = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ready: Bool { state.canClaimGift() && reward == nil }

    var body: some View {
        HStack(spacing: Space.m) {
            box
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                subtitle
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if ready {
                Button("Open", action: claim)
                    .shopButton()
                    .accessibilityHint("Opens today's free gift")
            }
        }
        .padding(Space.m)
        .shopCard()
        .overlay { GiftBurst(trigger: bursts) }
        .haptic(.success, trigger: bursts)
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        if let reward { return rewardText(reward) }
        return ready ? "Today's gift" : "Gift opened"
    }

    @ViewBuilder private var subtitle: some View {
        if ready {
            Text("Free, once a day, for both of you")
        } else {
            // A real rotation: the next gift is the next local day's.
            HStack(spacing: 4) {
                Text("A new one in")
                Text(timerInterval: Date.now...state.offers.nextDay(after: .now), countsDown: true)
                    .monospacedDigit()
            }
        }
    }

    private var box: some View {
        Image(systemName: ready ? "gift.fill" : "gift")
            .font(.system(.largeTitle))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.blushPink, Color.honey)
            .symbolEffect(.bounce, options: .repeat(.periodic(delay: 2.5)), isActive: ready && !reduceMotion)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 56, height: 56)
            .background(Ink.surfaceRaised, in: .rect(cornerRadius: Radius.control, style: .continuous))
            .accessibilityHidden(true)
    }

    private func rewardText(_ reward: GiftReward) -> String {
        switch reward {
        case .coins(let amount): "+\(amount) coins"
        case .item(let id): "\(Catalog.item(id)?.name ?? "A surprise") is yours"
        }
    }

    private func claim() {
        guard let got = state.claimGift() else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.45)) { reward = got }
        bursts += 1
    }
}

/// Coins, hearts and sparkles that pop out of the gift box once per trigger.
private struct GiftBurst: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pieces: [(symbol: String, color: Color, angle: Double, distance: CGFloat)] = (0..<14).map { i in
        let symbols = ["star.fill", "heart.fill", "sparkle", "circle.fill"]
        let colors: [Color] = [.honey, .blushPink, Color(hex: 0xFFD76A), .honeyDeep]
        return (symbols[i % 4], colors[(i / 2) % 4], Double(i) / 14 * 360 + Double(i % 3) * 9, CGFloat(46 + (i * 17) % 40))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Self.pieces.indices, id: \.self) { i in
                    let piece = Self.pieces[i]
                    Image(systemName: piece.symbol)
                        .font(.system(size: 11 + CGFloat(i % 3) * 3, weight: .bold))
                        .foregroundStyle(piece.color)
                        .keyframeAnimator(initialValue: BurstFrame(), trigger: trigger) { content, frame in
                            content
                                .offset(x: cos(piece.angle * .pi / 180) * piece.distance * frame.spread,
                                        y: sin(piece.angle * .pi / 180) * piece.distance * frame.spread + frame.fall)
                                .scaleEffect(frame.scale)
                                .opacity(frame.opacity)
                        } keyframes: { _ in
                            KeyframeTrack(\.spread) { SpringKeyframe(1, duration: 0.5, spring: .bouncy) }
                            KeyframeTrack(\.fall) {
                                LinearKeyframe(0, duration: 0.3)
                                LinearKeyframe(24, duration: 0.6)
                            }
                            KeyframeTrack(\.scale) {
                                SpringKeyframe(1, duration: 0.3)
                                LinearKeyframe(0.6, duration: 0.6)
                            }
                            KeyframeTrack(\.opacity) {
                                LinearKeyframe(1, duration: 0.05)
                                LinearKeyframe(1, duration: 0.45)
                                LinearKeyframe(0, duration: 0.4)
                            }
                        }
                }
            }
            // The box sits at the card's leading edge.
            .position(x: Space.m + 28, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .opacity(trigger == 0 || reduceMotion ? 0 : 1)
    }
}

private struct BurstFrame {
    var spread: CGFloat = 0
    var fall: CGFloat = 0
    var scale: CGFloat = 0.2
    var opacity: Double = 0
}
