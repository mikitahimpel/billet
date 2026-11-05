import SwiftUI

/// An item on the Shop: its art large and lifted in the rarity frame, the name, what it does for Mochi, and its
/// price pill, which buys it in one tap. `large` is the art-first card of the daily deals.
struct ShopItemCard: View {
    let item: ShopItem
    let state: HomeState
    var large = false
    var onTap: () -> Void

    private var owned: Bool { state.owned.contains(item.id) }
    private var price: Int { state.price(of: item) }
    private var isDeal: Bool { price < item.price }

    var body: some View {
        // The art and the name open the item's sheet; the price pill under them buys it in one tap.
        VStack(alignment: .leading, spacing: Space.s) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: Space.s) {
                    art
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(large ? .nookiTitle : .nookiHeadline)
                            .foregroundStyle(Ink.text)
                            .lineLimit(2)
                        if let mood = item.mood {
                            Text("\(state.petName): \(mood)")
                                .font(.nookiCaption)
                                .foregroundStyle(Ink.accentText)
                                .lineLimit(1)
                        }
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
                        buy: { state.buy(item) }, fills: true)
        }
        .padding(large ? Space.m : Space.s + 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .shopCard(radius: large ? Radius.hero : Radius.card)
    }

    private var art: some View {
        RarityFrame(rarity: item.rarity) {
            if let image = Thumbnails.image(item.thumbnail, maxPixels: 512) {
                Lifted {
                    Image(uiImage: image).resizable().scaledToFit()
                }
                .padding(large ? Space.l : Space.s)
                .padding(.bottom, Space.xs)
            } else {
                Image(systemName: "cube.box").font(.largeTitle).foregroundStyle(Ink.textTertiary)
            }
        }
        .aspectRatio(large ? 1 : 1.05, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            ShopTag(text: item.rarity.title, fill: item.rarity.tint).padding(Space.s)
        }
        .overlay(alignment: .topTrailing) {
            if isDeal, !owned {
                ShopTag(text: "−\(Int(((1 - Double(price) / Double(item.price)) * 100).rounded()))%",
                        fill: ShopInk.coral)
                    .scaleEffect(large ? 1.25 : 1, anchor: .topTrailing)
                    .rotationEffect(.degrees(4))
                    .padding(Space.s)
            } else if item.isNew, !owned {
                ShopTag(text: "New", fill: .honey).padding(Space.s)
            }
        }
    }
}
