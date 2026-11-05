import SwiftUI

/// The week's hero offer at the top of Today: the set's pieces large on lamplight, its value against the sum of the
/// missing parts, and a countdown to the real Monday rotation. The price pill buys it in one tap.
struct FeaturedCard: View {
    let state: HomeState
    let offer: FeaturedOffer
    /// Opens the set's sheet.
    var openSet: (FeaturedOffer) -> Void = { _ in }

    private var quote: (price: Int, sum: Int)? { ShopOffers.price(of: offer, owned: state.shop.owned) }
    private var items: [ShopItem] { offer.itemIDs.compactMap(Catalog.item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                Label {
                    (Text("New in ") + Text(offer.endsAt, style: .relative))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.nookiMicro)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glass(.capsule, tint: Ink.heroInk.opacity(0.25))

                Spacer(minLength: 0)
                if let quote, quote.price > 0, quote.sum > quote.price {
                    ValueBadge(multiple: valueText(quote), saves: quote.sum - quote.price)
                }
            }

            Button { openSet(offer) } label: {
                art
                    .frame(maxWidth: .infinity)
                    .frame(height: 196)
                    .contentShape(.rect)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("\(offer.name), see the pieces")

            HStack(alignment: .center, spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.name)
                        .font(.nookiTitle)
                        .foregroundStyle(.white)
                    Text(offer.blurb)
                        .font(.nookiCaption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SetBuyButton(state: state, set: offer, ownedInk: .white)
            }
            .padding(Space.m)
            .glass(.rect(cornerRadius: Radius.card, style: .continuous), tint: Ink.heroInk.opacity(0.3))
        }
        .padding(Space.m)
        .background {
            // The glow is the card's shape's own, so the countdown ticking inside never redraws it.
            RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                .fill(ShopInk.lamplight)
                .shadow(color: ShopInk.coral.opacity(0.4), radius: 18, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }

    /// The set against its parts, e.g. "2" for half price; one decimal when it isn't whole.
    private func valueText(_ quote: (price: Int, sum: Int)) -> String {
        let value = Double(quote.sum) / Double(quote.price)
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// The pieces stand side by side, the middle one larger and in front, as large as the card's width lets them.
    private var art: some View {
        GeometryReader { proxy in
            let overlap = Space.l
            let others = CGFloat(max(0, items.count - 1))
            // The side pieces are 72% of the middle one and each overlaps its neighbour by `overlap`.
            let centre = min(176, proxy.size.height, (proxy.size.width + others * overlap) / (1 + others * 0.72))
            HStack(alignment: .bottom, spacing: -overlap) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let isCentre = index == items.count / 2
                    Lifted {
                        if let image = Thumbnails.trimmed(item.thumbnail) {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            Image(systemName: "cube.box").font(.largeTitle).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .frame(width: isCentre ? centre : centre * 0.72, height: isCentre ? centre : centre * 0.72)
                    .zIndex(isCentre ? 1 : 0)
                    .opacity(state.shop.owned.contains(item.id) ? 0.45 : 1)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

/// The hero's sticker: what the set is worth against its missing pieces bought one by one, and the coins it saves.
private struct ValueBadge: View {
    let multiple: String
    let saves: Int

    var body: some View {
        VStack(spacing: 0) {
            Text("×\(multiple)")
                .font(.nookiTitle.monospacedDigit())
            Text("value · save \(saves)")
                .font(.nookiMicro.monospacedDigit())
        }
        .foregroundStyle(Ink.heroInk)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xs + 2)
        .background(ShopInk.gold, in: .rect(cornerRadius: Radius.control, style: .continuous))
        .rotationEffect(.degrees(5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(multiple) times the value, saves \(saves) coins")
    }
}
