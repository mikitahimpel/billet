import SwiftUI
import Design

/// An `ItemCard`: the same name line, two-line blurb and buy row under every item's art, so a row of cards is level
/// whatever each one costs or whether it is owned.
struct ShopItemCard: View {
    let item: ShopItem
    let state: HomeState
    var onTap: () -> Void

    private var owned: Bool { state.shop.owned.contains(item.id) }
    private var price: Int { state.shop.price(of: item) }
    private var isDeal: Bool { price < item.price }

    var body: some View {
        // The art and the name open the item's sheet; the buy under them buys it in one tap.
        ItemCard(item.name, subtitle: item.blurb, open: onTap) {
            art
        } leadingBadge: {
            item.rarity.chip
        } trailingBadge: {
            if isDeal, !owned {
                Chip("−\(Int(((1 - Double(price) / Double(item.price)) * 100).rounded()))%", style: .honey)
            } else if item.isNew, !owned {
                Chip("New", style: .honey)
            } else if owned {
                Chip("Owned", symbol: "checkmark")
            }
        } footer: {
            BuyButton(state: state, quote: owned ? nil : (price: price, sum: item.price), name: item.name,
                      buy: { state.shop.buy(item) }, fills: true)
        }
        .perfFlattened()
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
    }
}
