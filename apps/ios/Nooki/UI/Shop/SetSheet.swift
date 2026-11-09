import SwiftUI
import Design

/// Which set's sheet is open: the week's featured set or a bundle.
struct SetChoice: Identifiable {
    let pieces: any PieceSet
    var id: String { pieces.id }
}

/// A set's card: the name with what it saves, its pieces with their rarity and own price, and one buy button with
/// the set's price beside the sum it replaces. Pieces already owned are left out of the price and marked.
struct SetSheet: View {
    let state: HomeState
    let pieces: any PieceSet

    @Environment(\.dismiss) private var dismiss

    private var items: [ShopItem] { pieces.itemIDs.compactMap(Catalog.item) }
    private var quote: (price: Int, sum: Int)? { ShopOffers.price(of: pieces, owned: state.shop.owned) }
    private var affordable: Bool { quote.map { state.shop.coins >= $0.price } ?? false }

    var body: some View {
        BilletSheet(pieces.name, size: .fit) {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(spacing: Space.s) {
                    if let quote, quote.sum > quote.price {
                        Chip("−\(Int(((1 - Double(quote.price) / Double(quote.sum)) * 100).rounded()))%", style: .honey)
                    }
                    Chip("\(items.count) pieces")
                }

                art

                Text(pieces.blurb)
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupedSection(inset: 56 + Space.m + Space.l) {
                    ForEach(items) { item in row(item) }
                }

                actions
            }
        }
        // A buy the coins don't cover opens the Coins sheet, which can't show over this one.
        .onChange(of: state.shop.coinsAsk) { _, ask in if ask != nil { dismiss() } }
    }

    /// The pieces side by side on the warm stage, the middle one larger and in front.
    private var art: some View {
        HStack(alignment: .bottom, spacing: -Space.l) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let centre = index == items.count / 2
                Group {
                    if let image = Thumbnails.trimmed(item.thumbnail) {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                }
                .frame(width: centre ? 136 : 96, height: centre ? 136 : 96)
                .zIndex(centre ? 1 : 0)
                .opacity(state.shop.owned.contains(item.id) ? 0.45 : 1)
            }
        }
        .padding(.horizontal, Space.m)
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(ShopInk.lamplight, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .accessibilityHidden(true)
    }

    private func row(_ item: ShopItem) -> some View {
        let owned = state.shop.owned.contains(item.id)
        return HStack(spacing: Space.m) {
            RarityFrame(rarity: item.rarity) {
                if let image = Thumbnails.image(item.thumbnail, maxPixels: 256) {
                    Image(uiImage: image).resizable().scaledToFit().padding(Space.xs)
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Text(item.rarity.title)
                    .font(.nookiCaption)
                    .foregroundStyle(item.rarity == .common ? Ink.textSecondary : item.rarity.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if owned {
                Label("Owned", systemImage: "checkmark.circle.fill")
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
            } else {
                CoinPrice(price: state.shop.price(of: item))
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: Space.s) {
            if let quote {
                Button(action: buy) {
                    HStack(spacing: Space.s) {
                        if affordable {
                            Text("Buy the set for")
                            CoinPrice(price: quote.price, was: quote.sum)
                        } else {
                            Image(systemName: "plus.circle.fill")
                            Text("Need \(quote.price - state.shop.coins) more coins").monospacedDigit()
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                if !affordable {
                    Text("Earn coins by answering today's question, keeping your streak and opening the daily gift.")
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Button {
                    state.tab = .world
                    dismiss()
                } label: {
                    Label("Place in your room", systemImage: "house.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                Label("The whole set is in your closet", systemImage: "checkmark.circle.fill")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func buy() {
        guard state.shop.buy(pieces) else { return }
        // The purchase moment plays over the app once the sheet is out of the way.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            dismiss()
        }
    }
}
