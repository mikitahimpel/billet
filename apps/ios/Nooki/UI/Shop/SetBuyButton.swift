import SwiftUI

/// Buys a set's missing pieces: the price in coins next to the struck-through sum, then one confirmation naming the
/// pieces. "Owned" once the couple has them all.
struct SetBuyButton<Pieces: PieceSet>: View {
    let state: HomeState
    let set: Pieces
    /// The "Owned" label's colour: white on the featured art, the text colour on a card.
    var ownedInk: Color = Ink.text

    @State private var confirming = false

    private var quote: (price: Int, sum: Int)? { ShopOffers.price(of: set, owned: state.owned) }

    var body: some View {
        Group {
            if let quote {
                let affordable = state.coins >= quote.price
                Button { confirming = true } label: {
                    CoinPrice(price: quote.price, was: quote.sum)
                }
                .shopButton()
                .disabled(!affordable)
                .accessibilityHint(affordable ? "Buys the \(set.name) set" : "Needs \(quote.price - state.coins) more coins")
            } else {
                Label("Owned", systemImage: "checkmark")
                    .font(.nookiHeadline)
                    .foregroundStyle(ownedInk)
            }
        }
        .confirmationDialog(dialogTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button("Buy for \(quote?.price ?? 0) coins") {
                state.buy(set)
            }
            Button("Not now", role: .cancel) {}
        }
    }

    private var dialogTitle: String {
        let names = set.itemIDs.filter { !state.owned.contains($0) }.compactMap { Catalog.item($0)?.name }
        return "\(set.name): \(names.formatted(.list(type: .and)))"
    }
}
