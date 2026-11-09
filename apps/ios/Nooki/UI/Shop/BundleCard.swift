import SwiftUI
import Design

struct BundleCard: View {
    let state: HomeState
    let bundle: ShopBundle
    var open: (ShopItem) -> Void
    var openSet: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var items: [ShopItem] { bundle.itemIDs.compactMap(Catalog.item) }
    private var quote: (price: Int, sum: Int)? { ShopOffers.price(of: bundle, owned: state.shop.owned) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            pieces
            // The button sits beside the title, which wraps; at accessibility text sizes it goes under it.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Space.m))
            layout {
                Button(action: openSet) {
                    title.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                }
                .buttonStyle(PressScaleStyle())
                SetBuyButton(state: state, set: bundle)
                    .fixedSize()
            }
        }
        .padding(CardMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Space.s) {
                Text(bundle.name)
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                if let quote, quote.sum > quote.price {
                    Chip("−\(Int(((1 - Double(quote.price) / Double(quote.sum)) * 100).rounded()))%", style: .honey)
                }
            }
            Text(bundle.blurb)
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pieces: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Image(systemName: "plus")
                        .font(.ourioCaption.weight(.bold))
                        .foregroundStyle(Ink.textTertiary)
                        .accessibilityHidden(true)
                }
                Button { open(item) } label: {
                    RarityFrame(rarity: item.rarity) {
                        if let image = Thumbnails.image(item.thumbnail, maxPixels: 256) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .padding(Space.s)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .overlay(alignment: .bottomTrailing) {
                        if state.shop.owned.contains(item.id) { OwnedCheck().offset(x: 4, y: 4) }
                    }
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(item.name + (state.shop.owned.contains(item.id) ? ", owned" : ""))
            }
        }
    }
}

struct OwnedCheck: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.ourioCallout)
            .symbolRenderingMode(.palette)
            .foregroundStyle(Ink.heroInk, Color.honey)
            .background(Circle().fill(Ink.surface).padding(1))
            .accessibilityHidden(true)
    }
}
