#if canImport(UIKit)
  import Design
  import SwiftUI

  struct SetBuyButton<Pieces: PieceSet>: View {
    let state: any ShopHost
    let set: Pieces

    var body: some View {
      BuyButton(
        state: state, quote: state.shop.offers.price(of: set, owned: state.shop.owned),
        name: set.name,
        buy: { state.shop.buy(set) })
    }
  }
#endif
