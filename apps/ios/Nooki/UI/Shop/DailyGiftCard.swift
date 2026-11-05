import SwiftUI

/// The free gift in Today: one tap asks the server to open it, the box shakes open with the reward it gave, and a new
/// gift comes at local midnight.
struct DailyGiftCard: View {
    let state: HomeState

    @State private var reward: GiftReward?
    @State private var bursts = 0
    @State private var opening = false

    private var ready: Bool { state.shop.canClaimGift() && reward == nil }

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
                Button("Open") { Task { await claim() } }
                    .shopButton()
                    .disabled(opening)
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
                Text(timerInterval: Date.now...state.shop.offers.nextDay(after: .now), countsDown: true)
                    .monospacedDigit()
            }
        }
    }

    private var box: some View {
        GiftBox(opened: !ready, opens: bursts, reward: reward)
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

    private func claim() async {
        opening = true
        defer { opening = false }
        switch await state.shop.openGift() {
        case .opened(let got):
            withAnimation(.spring(duration: 0.45, bounce: 0.45)) { reward = got }
            bursts += 1
        case .taken, nil:
            // Opened already (by the partner, or a try whose answer was lost): the card shows it as opened.
            break
        }
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

/// A drawn gift box. While it waits it gives a little wiggle now and then; opening shakes it, pops the lid off and
/// lifts the reward out. Under Reduce Motion it just shows the open box.
private struct GiftBox: View {
    let opened: Bool
    /// Bumped once per opening; drives the shake.
    let opens: Int
    let reward: GiftReward?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            prize
            boxBody
            lid
        }
        .frame(width: 44, height: 44)
        .keyframeAnimator(initialValue: Shake(), trigger: opens) { content, shake in
            content
                .rotationEffect(.degrees(reduceMotion ? 0 : shake.angle), anchor: .bottom)
                .scaleEffect(x: reduceMotion ? 1 : shake.squash, y: reduceMotion ? 1 : 2 - shake.squash, anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack(\.angle) {
                LinearKeyframe(-10, duration: 0.06)
                LinearKeyframe(10, duration: 0.08)
                LinearKeyframe(-8, duration: 0.08)
                LinearKeyframe(6, duration: 0.08)
                SpringKeyframe(0, duration: 0.3)
            }
            KeyframeTrack(\.squash) {
                LinearKeyframe(1, duration: 0.3)
                LinearKeyframe(1.12, duration: 0.08)
                SpringKeyframe(1, duration: 0.35, spring: .bouncy)
            }
        }
        .phaseAnimator([0.0, -7, 7, 0], trigger: opened || reduceMotion ? 0 : idleTicks) { content, angle in
            content.rotationEffect(.degrees(angle), anchor: .bottom)
        } animation: { _ in .easeInOut(duration: 0.09) }
        .task(id: opened) {
            // A wiggle every few seconds while the gift waits.
            while !opened, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                idleTicks += 1
            }
        }
    }

    @State private var idleTicks = 0

    private var boxBody: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xFF9DB0), Color(hex: 0xF07A92)], startPoint: .top, endPoint: .bottom))
            .frame(width: 34, height: 24)
            .overlay(Rectangle().fill(Color(hex: 0xFFE2A8)).frame(width: 6))
    }

    private var lid: some View {
        VStack(spacing: -2) {
            bow
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFB3C2), Color.blushPink], startPoint: .top, endPoint: .bottom))
                .frame(width: 40, height: 10)
                .overlay(Rectangle().fill(Color(hex: 0xFFE2A8)).frame(width: 6))
        }
        .offset(x: opened ? 12 : 0, y: opened ? -34 : -22)
        .rotationEffect(.degrees(opened ? 24 : 0))
        .opacity(opened ? 0 : 1)
        .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.4).delay(0.3), value: opened)
    }

    private var bow: some View {
        HStack(spacing: 0) {
            Circle().strokeBorder(Color(hex: 0xFFE2A8), lineWidth: 3).frame(width: 10, height: 10)
            Circle().strokeBorder(Color(hex: 0xFFE2A8), lineWidth: 3).frame(width: 10, height: 10)
        }
    }

    /// What was inside, rising out of the open box.
    @ViewBuilder private var prize: some View {
        Group {
            switch reward {
            case .coins: CoinIcon(size: 22)
            case .item(let id):
                if let image = Thumbnails.image("Item_\(id)", maxPixels: 128) {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: 30, height: 30)
                }
            case nil: EmptyView()
            }
        }
        .offset(y: reward == nil ? -6 : -24)
        .scaleEffect(reward == nil ? 0.3 : 1)
        .opacity(reward == nil ? 0 : 1)
        .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.5).delay(0.45), value: reward)
    }
}

private struct Shake {
    var angle: Double = 0
    var squash: CGFloat = 1
}
