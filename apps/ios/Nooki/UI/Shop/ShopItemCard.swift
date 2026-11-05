import SwiftUI

/// An item in a grid: its art in the rarity frame, the name, what it does for Mochi, and the price or "Owned".
struct ShopItemCard: View {
    let item: ShopItem
    let state: HomeState
    var onTap: () -> Void

    private var owned: Bool { state.owned.contains(item.id) }
    private var price: Int { state.price(of: item) }
    private var isDeal: Bool { price < item.price }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Space.s) {
                art
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.nookiHeadline)
                        .foregroundStyle(Ink.text)
                        .lineLimit(2)
                    if let mood = item.mood {
                        Text("\(state.petName): \(mood)")
                            .font(.nookiCaption)
                            .foregroundStyle(Ink.accentText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                footer
            }
            .padding(Space.s + 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .shopCard()
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(item.name)")
    }

    private var art: some View {
        RarityFrame(rarity: item.rarity) {
            if let image = Thumbnails.image(item.thumbnail, maxPixels: 512) {
                Image(uiImage: image).resizable().scaledToFit().padding(Space.s)
            } else {
                Image(systemName: "cube.box").font(.largeTitle).foregroundStyle(Ink.textTertiary)
            }
        }
        .aspectRatio(1.1, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            ShopTag(text: item.rarity.title, fill: item.rarity.tint).padding(6)
        }
        .overlay(alignment: .topTrailing) {
            if isDeal, !owned {
                ShopTag(text: "−\(Int(((1 - Double(price) / Double(item.price)) * 100).rounded()))%",
                        fill: .blushPink)
                    .padding(6)
            } else if item.isNew, !owned {
                ShopTag(text: "New", fill: .honey, ink: Ink.heroInk).padding(6)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if owned {
            Label("Owned", systemImage: "checkmark")
                .font(.nookiCallout)
                .foregroundStyle(Ink.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 34)
        } else {
            CoinPrice(price: price, was: isDeal ? item.price : nil)
                .font(.nookiHeadline)
                .foregroundStyle(isDeal ? Ink.heroInk : Ink.text)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(isDeal ? AnyShapeStyle(Color.honey) : AnyShapeStyle(Ink.surfaceRaised), in: .capsule)
        }
    }
}
