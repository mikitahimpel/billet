import SwiftUI

/// The week's hero offer: the set's pieces on warm art, its value against the sum of its parts, and a countdown to
/// the real Monday rotation. Buying asks once, with the price in coins.
struct FeaturedCard: View {
    let state: HomeState
    let offer: FeaturedOffer

    private var quote: (price: Int, sum: Int)? { ShopOffers.price(of: offer, owned: state.owned) }
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

                if let quote, quote.price > 0 {
                    ShopTag(text: "×\(valueText(quote)) value", fill: Color(hex: 0xFFC27D), ink: Ink.heroInk)
                        .rotationEffect(.degrees(-4))
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                }
                Spacer(minLength: 0)
            }

            art
                .frame(maxWidth: .infinity)
                .frame(height: 150)

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
        .background(backdrop, in: .rect(cornerRadius: Radius.hero, style: .continuous))
        .shadow(color: Color.honeyDeep.opacity(0.35), radius: 16, y: 8)
    }

    /// The set against its parts, e.g. "2" for half price; one decimal when it isn't whole.
    private func valueText(_ quote: (price: Int, sum: Int)) -> String {
        let value = Double(quote.sum) / Double(quote.price)
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// The pieces stand side by side, the middle one larger and in front.
    private var art: some View {
        HStack(alignment: .bottom, spacing: -Space.l) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let centre = index == items.count / 2
                Group {
                    if let image = Thumbnails.trimmed(item.thumbnail) {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Image(systemName: "cube.box").font(.largeTitle).foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(width: centre ? 140 : 104, height: centre ? 140 : 104)
                .zIndex(centre ? 1 : 0)
                .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
                .opacity(state.owned.contains(item.id) ? 0.45 : 1)
            }
        }
        .accessibilityHidden(true)
    }

    /// Lamplight on a warm room: a stand-in until the in-room render of each set.
    private var backdrop: some ShapeStyle {
        RadialGradient(colors: [Color(hex: 0xF7C98E), Color(hex: 0xC97A45), Color(hex: 0x5A3420)],
                       center: UnitPoint(x: 0.55, y: 0.38), startRadius: 10, endRadius: 320)
    }
}
