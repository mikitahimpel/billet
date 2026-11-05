import SwiftUI

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
    @State private var height: CGFloat = 600

    private var items: [ShopItem] { pieces.itemIDs.compactMap(Catalog.item) }
    private var quote: (price: Int, sum: Int)? { ShopOffers.price(of: pieces, owned: state.owned) }
    private var affordable: Bool { quote.map { state.coins >= $0.price } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SheetHeader(title: pieces.name) {
                if let quote, quote.sum > quote.price {
                    ShopTag(text: "−\(Int(((1 - Double(quote.price) / Double(quote.sum)) * 100).rounded()))%",
                            fill: .blushPink)
                }
                ShopTag(text: "\(items.count) pieces", fill: Ink.surfaceRaised, ink: Ink.text)
            } close: { dismiss() }

            art

            Text(pieces.blurb)
                .font(.nookiCallout)
                .foregroundStyle(Ink.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Ink.separator).padding(.leading, 56 + Space.m) }
                    row(item)
                }
            }
            .padding(.horizontal, Space.m)
            .background(Ink.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))

            actions
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.gutter)
        .padding(.bottom, Space.s)
        .shopSheet(height: $height)
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
                .frame(width: centre ? 150 : 110, height: centre ? 150 : 110)
                .zIndex(centre ? 1 : 0)
                .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
                .opacity(state.owned.contains(item.id) ? 0.45 : 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(RadialGradient(colors: [Color(hex: 0xF7C98E), Color(hex: 0xC97A45), Color(hex: 0x5A3420)],
                                   center: UnitPoint(x: 0.55, y: 0.4), startRadius: 10, endRadius: 280),
                    in: .rect(cornerRadius: Radius.hero, style: .continuous))
        .accessibilityHidden(true)
    }

    private func row(_ item: ShopItem) -> some View {
        let owned = state.owned.contains(item.id)
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
                CoinPrice(price: state.price(of: item))
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
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
                            Image(systemName: "lock.fill")
                            Text("Need \(quote.price - state.coins) more coins").monospacedDigit()
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                }
                .nookiPrimary()
                .disabled(!affordable)
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
                .nookiPrimary()
                Label("The whole set is in your closet", systemImage: "checkmark.circle.fill")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func buy() {
        guard state.buy(pieces) else { return }
        // The purchase moment plays over the app once the sheet is out of the way.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            dismiss()
        }
    }
}
