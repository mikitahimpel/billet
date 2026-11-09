import AudioToolbox
import SwiftUI
import Design

/// What plays over the app after a buy: coins burst where it happened, the pieces fly down into a card where Mochi
/// hops at the news, a tink and a success haptic, and Undo for five seconds. Under Reduce Motion only the card shows.
/// A buy the server then refuses is taken back with a gentle line in the same place.
struct PurchaseMoment: View {
    let state: HomeState

    @State private var shown: Purchase?
    @State private var refused: Purchase?
    @State private var flights = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
            // Just above the tab bar, where the card sits.
            let landing = CGPoint(x: 52, y: proxy.size.height - 132)
            ZStack {
                if let shown, !reduceMotion {
                    ZStack {
                        CoinBurst(trigger: flights)
                            .position(centre)
                        ForEach(Array(shown.itemIDs.prefix(4).enumerated()), id: \.element) { index, id in
                            FlyingPiece(id: id, from: centre, to: landing, delay: Double(index) * 0.08, trigger: flights)
                        }
                    }
                    .allowsHitTesting(false)
                }
                VStack {
                    Spacer()
                    if let shown {
                        card(shown)
                            .padding(.horizontal, Space.l)
                            .padding(.bottom, 92)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let refused {
                        refusal(refused)
                            .padding(.horizontal, Space.l)
                            .padding(.bottom, 92)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .haptic(.success, trigger: flights)
        .onChange(of: state.shop.lastPurchase) { _, purchase in
            guard let purchase else {
                withAnimation(.spring(duration: 0.3)) { shown = nil }
                return
            }
            withAnimation(.spring(duration: 0.45, bounce: 0.3).delay(reduceMotion ? 0 : 0.55)) { shown = purchase }
            flights += 1
            AudioServicesPlaySystemSound(1057)
        }
        .onChange(of: state.shop.refused) { _, purchase in
            withAnimation(.spring(duration: 0.35)) {
                if purchase != nil { shown = nil }
                refused = purchase
            }
        }
        .task(id: refused?.id) {
            guard let current = refused else { return }
            try? await Task.sleep(for: .seconds(4))
            if refused?.id == current.id { withAnimation(.spring(duration: 0.35)) { refused = nil } }
        }
        .task(id: shown?.id) {
            // The card leaves when Undo would no longer work, counted from the buy itself.
            guard let current = shown else { return }
            let left = Purchase.undoWindow - Date.now.timeIntervalSince(current.date)
            try? await Task.sleep(for: .seconds(max(0, left)))
            if shown?.id == current.id { withAnimation(.spring(duration: 0.35)) { shown = nil } }
        }
    }

    private func detail(_ purchase: Purchase) -> String {
        switch purchase.kind {
        case .item: "\(state.petName) is already sniffing it. It's in your room's closet."
        case .ink: "It's in your pens for notes and drawings, for both of you."
        case .treat: "\(state.petName) loved it."
        }
    }

    private func card(_ purchase: Purchase) -> some View {
        HStack(spacing: Space.m) {
            MochiHop(trigger: flights)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(purchase.title) is yours")
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                    .lineLimit(2)
                Text(detail(purchase))
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SecondaryButton("Undo", fullWidth: false) {
                if state.shop.undo(purchase) { withAnimation(.spring(duration: 0.3)) { shown = nil } }
            }
            .accessibilityHint("Gives back \(purchase.cost) coins")
        }
        .padding(CardMetrics.padding)
        .cardSurface()
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }

    private func refusal(_ purchase: Purchase) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.ourioTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.honey)
                .accessibilityHidden(true)
            Text("Couldn't buy \(purchase.title). Your coins are back.")
                .font(.ourioCallout)
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(CardMetrics.padding)
        .cardSurface()
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("purchaseRefused")
    }
}

/// Mochi's round avatar, hopping once per buy.
private struct MochiHop: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let image = UIImage(named: CatCoat.current().avatar) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "cat.fill").font(.title2).foregroundStyle(Color.honey)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(.circle)
        .keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { content, lift in
            content.offset(y: reduceMotion ? 0 : -lift)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0, duration: 0.6)
                SpringKeyframe(14, duration: 0.18)
                SpringKeyframe(0, duration: 0.3, spring: .bouncy)
                SpringKeyframe(8, duration: 0.15)
                SpringKeyframe(0, duration: 0.3, spring: .bouncy)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One piece's art lifting a little, then arcing down into the card and shrinking away.
private struct FlyingPiece: View {
    let id: String
    let from: CGPoint
    let to: CGPoint
    let delay: Double
    let trigger: Int

    var body: some View {
        Group {
            if let image = Thumbnails.image("Item_\(id)", maxPixels: 256) {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .frame(width: 110, height: 110)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 5)
        .keyframeAnimator(initialValue: Flight(), trigger: trigger) { content, flight in
            content
                .scaleEffect(flight.scale)
                .opacity(flight.opacity)
                .position(x: from.x + (to.x - from.x) * flight.progress,
                          y: from.y + (to.y - from.y) * flight.progress - flight.lift)
        } keyframes: { _ in
            KeyframeTrack(\.progress) {
                LinearKeyframe(0, duration: 0.15 + delay)
                CubicKeyframe(1, duration: 0.55)
            }
            KeyframeTrack(\.lift) {
                LinearKeyframe(0, duration: delay)
                SpringKeyframe(60, duration: 0.25)
                CubicKeyframe(0, duration: 0.45)
            }
            KeyframeTrack(\.scale) {
                LinearKeyframe(0.6, duration: delay)
                SpringKeyframe(1.1, duration: 0.2, spring: .bouncy)
                CubicKeyframe(0.25, duration: 0.5)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: delay + 0.05)
                LinearKeyframe(1, duration: 0.6)
                LinearKeyframe(0, duration: 0.15)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct Flight {
    var progress: CGFloat = 0
    var lift: CGFloat = 0
    var scale: CGFloat = 0.6
    var opacity: Double = 0
}

/// Coins that spray out of the spot where the buy happened.
private struct CoinBurst: View {
    let trigger: Int

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                let angle = Double(i) / 12 * 2 * .pi + Double(i % 3) * 0.2
                let distance = CGFloat(70 + (i * 23) % 50)
                CoinIcon(size: 18 + CGFloat(i % 3) * 4)
                    .keyframeAnimator(initialValue: Spray(), trigger: trigger) { content, spray in
                        content
                            .offset(x: cos(angle) * distance * spray.spread,
                                    y: sin(angle) * distance * spray.spread + spray.fall)
                            .opacity(spray.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.spread) { SpringKeyframe(1, duration: 0.5, spring: .bouncy) }
                        KeyframeTrack(\.fall) {
                            LinearKeyframe(0, duration: 0.35)
                            LinearKeyframe(40, duration: 0.5)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1, duration: 0.05)
                            LinearKeyframe(1, duration: 0.45)
                            LinearKeyframe(0, duration: 0.35)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct Spray {
    var spread: CGFloat = 0
    var fall: CGFloat = 0
    var opacity: Double = 0
}
