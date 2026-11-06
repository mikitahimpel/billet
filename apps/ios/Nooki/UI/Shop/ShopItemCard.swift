import SwiftUI

/// An item on the Shop: its art large and lifted in the rarity frame, the name, what it does for Mochi, and its
/// price pill, which buys it in one tap.
struct ShopItemCard: View {
    let item: ShopItem
    let state: HomeState
    var onTap: () -> Void

    private var owned: Bool { state.shop.owned.contains(item.id) }
    private var price: Int { state.shop.price(of: item) }
    private var isDeal: Bool { price < item.price }

    var body: some View {
        // The art and the name open the item's sheet; the price pill under them buys it in one tap.
        VStack(alignment: .leading, spacing: Space.s) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: Space.s) {
                    art
                    VStack(alignment: .leading, spacing: 2) {
                        // Both lines are always there, so the cards in a row are the same height.
                        Text(item.name)
                            .font(.nookiHeadline)
                            .foregroundStyle(Ink.text)
                            .lineLimit(2, reservesSpace: true)
                        Text(item.mood.map { "\(state.petName): \($0)" } ?? " ")
                            .font(.nookiCaption)
                            .foregroundStyle(Ink.accentText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens \(item.name)")
            Spacer(minLength: 0)
            PriceButton(state: state, quote: owned ? nil : (price: price, sum: item.price), name: item.name,
                        buy: { state.shop.buy(item) }, fills: true)
        }
        .padding(Space.s + 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .shopCard()
    }

    private var art: some View {
        RarityFrame(rarity: item.rarity) {
            if let image = Thumbnails.image(item.thumbnail, maxPixels: 512) {
                Lifted {
                    Image(uiImage: image).resizable().scaledToFit()
                }
                .padding(Space.s)
                .padding(.bottom, Space.xs)
            } else {
                Image(systemName: "cube.box").font(.largeTitle).foregroundStyle(Ink.textTertiary)
            }
        }
        .aspectRatio(1.05, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            ShopTag(text: item.rarity.title, fill: item.rarity.tint).padding(Space.s)
        }
        .overlay(alignment: .topTrailing) {
            if isDeal, !owned {
                ShopTag(text: "−\(Int(((1 - Double(price) / Double(item.price)) * 100).rounded()))%",
                        fill: ShopInk.coral)
                    .padding(Space.s)
            } else if item.isNew, !owned {
                ShopTag(text: "New", fill: .honey).padding(Space.s)
            }
        }
    }
}
