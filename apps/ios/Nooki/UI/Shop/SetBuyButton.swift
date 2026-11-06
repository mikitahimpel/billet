import SwiftUI
import Design

/// Buys a set's missing pieces in one tap: the price in coins next to the struck-through sum. "Owned · Place" once
/// the couple has them all.
struct SetBuyButton<Pieces: PieceSet>: View {
    let state: HomeState
    let set: Pieces

    var body: some View {
        BuyButton(state: state, quote: ShopOffers.price(of: set, owned: state.shop.owned), name: set.name,
                  buy: { state.shop.buy(set) })
    }
}
