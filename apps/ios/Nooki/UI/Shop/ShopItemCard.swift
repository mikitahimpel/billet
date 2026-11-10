import SwiftUI
import Design

/// Every card has the same name line, two-line blurb and buy row under its art, so a row of cards is level whatever
/// each one costs or whether it is owned.
struct ShopItemCard: View {
    let item: ShopItem
    let state: HomeState
    var onTap: () -> Void

    private var owned: Bool { state.shop.owned.contains(item.id) }
    private var price: Int { state.shop.price(of: item) }
    private var isDeal: Bool { price < item.price }

    var body: some View {
        // The art and the name open the item's sheet; the buy under them buys it in one tap.
        VStack(alignment: .leading, spacing: Space.s) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: Space.s) {
                    art
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.ourioHeadline)
                            .foregroundStyle(Ink.text)
                            .lineLimit(1)
                        Text(item.blurb)
                            .font(.ourioCaption)
                            .foregroundStyle(Ink.textSecondary)
                            .lineLimit(2, reservesSpace: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens \(item.name)")
            BuyButton(state: state, quote: owned ? nil : (price: price, sum: item.price), name: item.name,
                      buy: { state.shop.buy(item) }, fills: true)
        }
        .padding(CardMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var art: some View {
        RarityFrame(rarity: item.rarity) {
            if let image = Thumbnails.image(item.thumbnail, maxPixels: 512) {
                // The thumbnail carries its own soft shadow; nothing is drawn under it.
                Image(uiImage: image).resizable().scaledToFit()
                    .padding(Space.s)
            } else {
                Image(systemName: "cube.box").font(.largeTitle).foregroundStyle(Ink.textTertiary)
            }
        }
        .aspectRatio(1.05, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            item.rarity.chip.padding(Space.s)
        }
        .overlay(alignment: .topTrailing) {
            if isDeal, !owned {
                Chip("−\(Int(((1 - Double(price) / Double(item.price)) * 100).rounded()))%", style: .honey)
                    .padding(Space.s)
            } else if item.isNew, !owned {
                Chip("New", style: .honey).padding(Space.s)
            } else if owned {
                Chip("Owned", symbol: "checkmark").padding(Space.s)
            }
        }
    }
}
