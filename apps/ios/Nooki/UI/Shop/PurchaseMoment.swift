import AudioToolbox
import DecorInterface
import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import UsInterface

/// Under Reduce Motion only the card shows. A buy the server then refuses is taken back with a gentle line in the
/// same place.
struct PurchaseMoment: View {
    let state: HomeState
    /// The top of the tab bar in global coordinates, which the card keeps clear of; nil where there is no bar.
    var floor: CGFloat? = nil

    @State private var shown: Purchase?
    @State private var refused: Purchase?
    @State private var flights = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let lift = Self.lift(bottom: proxy.frame(in: .global).maxY, floor: floor,
                                 safeBottom: proxy.safeAreaInsets.bottom)
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
            // On the cat at the card's leading edge.
            let landing = CGPoint(x: Space.l + CardMetrics.padding + 20, y: proxy.size.height - lift - 40)
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
                            .padding(.bottom, lift)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let refused {
                        refusal(refused)
                            .padding(.horizontal, Space.l)
                            .padding(.bottom, lift)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .haptic(.success, trigger: flights)
        .onChange(of: state.shop.lastPurchase) { _, purchase in
            guard let purchase else {
                withAnimation(Motion.spring(0.3)) { shown = nil }
                return
            }
            withAnimation(.spring(duration: 0.45, bounce: 0.3).delay(reduceMotion ? 0 : 0.55)) { shown = purchase }
            flights += 1
            AudioServicesPlaySystemSound(1057)
        }
        .onChange(of: state.shop.refused) { _, purchase in
            withAnimation(Motion.spring(0.35)) {
                if purchase != nil { shown = nil }
                refused = purchase
            }
        }
        .task(id: refused?.id) {
            guard let current = refused else { return }
            try? await Task.sleep(for: .seconds(4))
            if refused?.id == current.id { withAnimation(Motion.spring(0.35)) { refused = nil } }
        }
        .task(id: shown?.id) {
            // The card leaves when its Undo window ends, counted from the buy itself.
            guard let current = shown else { return }
            let left = Purchase.undoWindow - Date.now.timeIntervalSince(current.date)
            try? await Task.sleep(for: .seconds(max(0, left)))
            if shown?.id == current.id { withAnimation(Motion.spring(0.35)) { shown = nil } }
        }
    }

    private func detail(_ purchase: Purchase) -> String {
        switch purchase.kind {
        case .item:
            placedItem(purchase) == nil
                ? "\(state.petName) is already sniffing it. It's in your closet."
                : "\(state.petName) is already sniffing it. It's in your room."
        case .ink: "It's in your pens for notes and drawings, for both of you."
        case .treat: "\(state.petName) loved it."
        }
    }

    /// The piece of a buy that stands in the room, once it landed there by itself.
    private func placedItem(_ purchase: Purchase) -> String? {
        purchase.itemIDs.first { state.decor.state.layout.isPlaced($0) }
    }

    /// Place now for a piece waiting in the closet, Move it for one that landed in the room.
    @ViewBuilder private func decorateButton(_ purchase: Purchase) -> some View {
        let placed = placedItem(purchase)
        if let item = placed ?? purchase.itemIDs.first(where: { DecorItem.item(shopID: $0) != nil }) {
            PillButton(placed == nil ? "Place now" : "Move it", symbol: "mappin") {
                withAnimation(Motion.spring(0.3)) { shown = nil }
                state.decorate(item)
            }
            .fixedSize()
        }
    }

    /// How far above its container's bottom (`bottom`, global) the card sits: `Space.m` over the tab bar's top edge
    /// (`floor`), or `Space.l` over the home indicator where there is no bar.
    static func lift(bottom: CGFloat, floor: CGFloat?, safeBottom: CGFloat) -> CGFloat {
        guard let floor, floor < bottom else { return safeBottom + Space.l }
        return bottom - floor + Space.m
    }

    private func card(_ purchase: Purchase) -> some View {
        Toast {
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
                VStack(alignment: .trailing, spacing: Space.xs) {
                    if purchase.kind == .item { decorateButton(purchase) }
                    if purchase.undoable {
                        PillButton("Undo", symbol: "arrow.uturn.backward") {
                            if state.shop.undo(purchase) { withAnimation(Motion.spring(0.3)) { shown = nil } }
                        }
                        .fixedSize()
                        .accessibilityHint("Gives back \(purchase.cost) coins")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func refusal(_ purchase: Purchase) -> some View {
        Toast {
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
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("purchaseRefused")
    }
}

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
