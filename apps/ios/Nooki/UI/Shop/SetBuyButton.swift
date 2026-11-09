import SwiftUI
import Design

struct SetBuyButton<Pieces: PieceSet>: View {
    let state: HomeState
    let set: Pieces

    var body: some View {
        BuyButton(state: state, quote: ShopOffers.price(of: set, owned: state.shop.owned), name: set.name,
                  buy: { state.shop.buy(set) })
    }
}
