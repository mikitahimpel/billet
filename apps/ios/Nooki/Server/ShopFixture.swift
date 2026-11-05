#if DEBUG
import Foundation
import Transport
import Wire

/// A pair's room kept in memory, for UI tests: `-shopFixture YES` follows it instead of the server, starting from
/// `-shopCoins` and `-shopOwned`. It prices and charges orders as the server does, so a buy, its Undo and the balance
/// behave as with a real pair.
@MainActor
final class ShopFixture {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "shopFixture") }

    private let offers: ShopOffers
    private var balance: Int
    private var owned: Set<String>
    private var wishlist: [String] = []
    private var orders: Set<String> = []

    init(offers: ShopOffers, defaults: UserDefaults = .standard) {
        self.offers = offers
        balance = defaults.integer(forKey: "shopCoins")
        owned = Set((defaults.string(forKey: "shopOwned") ?? "").split(separator: ",").map(String.init))
    }

    var sync: ShopSync {
        ShopSync(
            fetch: { () async throws(TransportError) in await self.shop },
            order: { (request) async throws(TransportError) in try await self.order(request) },
            wish: { (request) async throws(TransportError) in await self.wish(request) })
    }

    private var shop: ShopResponse {
        let inks = owned.filter { id in PaletteInk.bundled.contains { $0.id == id } }
        return ShopResponse(
            balance: balance, inks: [.free] + inks.sorted().map(InkId.init),
            items: owned.subtracting(inks).sorted().map(RoomItemId.init), wishlist: wishlist.map(RoomItemId.init))
    }

    private func order(_ request: OrderRequest) throws(TransportError) -> OrderResponse {
        let entry = { (amount: Int) in
            CoinEntry(id: "spend:\(request.id.rawValue)", kind: .spend, amount: -amount, ref: "fixture", at: 0)
        }
        guard orders.insert(request.id.rawValue).inserted else { return OrderResponse(entry: entry(0), shop: shop) }
        let (cost, added) = try quote(request.offer)
        guard balance >= cost else { throw .api(.notEnoughCoins(needed: cost, have: balance)) }
        balance -= cost
        owned.formUnion(added)
        wishlist.removeAll(where: added.contains)
        return OrderResponse(entry: entry(cost), shop: shop)
    }

    private func quote(_ offer: ShopOffer) throws(TransportError) -> (Int, [String]) {
        switch offer {
        case .treat:
            return (ShopModel.treatPrice, [])
        case .item(let id):
            guard let item = Catalog.item(id.rawValue) else { throw .api(.invalidRequest) }
            guard !owned.contains(item.id) else { throw .api(.alreadyOwned(itemId: item.id)) }
            return (offers.deal(for: item.id, on: .now)?.price(of: item) ?? item.price, [item.id])
        case .ink(let id):
            guard let ink = PaletteInk.bundled.first(where: { $0.wireID == id }) else { throw .api(.invalidRequest) }
            guard !ink.isOwned(owned) else { throw .api(.alreadyOwned(itemId: ink.id)) }
            return (ink.price, [ink.id])
        case .set(let id):
            let sets: [any PieceSet] = [offers.featured(on: .now)] + ShopOffers.bundles
            guard let set = sets.first(where: { $0.id == id.rawValue }) else { throw .api(.invalidRequest) }
            guard let quote = ShopOffers.price(of: set, owned: owned) else {
                throw .api(.alreadyOwned(itemId: set.id))
            }
            return (quote.price, set.itemIDs.filter { !owned.contains($0) })
        }
    }

    private func wish(_ request: WishRequest) -> ShopResponse {
        wishlist.removeAll { $0 == request.item.rawValue }
        if request.wished { wishlist.append(request.item.rawValue) }
        return shop
    }
}
#endif
