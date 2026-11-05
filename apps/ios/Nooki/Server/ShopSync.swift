import Transport
import Wire

/// The pair's shop and wallet on the server: what it has, and every request that changes it. The server prices every
/// order and keeps the only balance; the app's prices are only shown.
struct ShopSync: Sendable {
    var fetch: @Sendable () async throws(TransportError) -> ShopResponse
    var order: @Sendable (OrderRequest) async throws(TransportError) -> OrderResponse
    var wish: @Sendable (WishRequest) async throws(TransportError) -> ShopResponse
    /// The inks on sale.
    var inks: @Sendable () async throws(TransportError) -> InksResponse = {
        () async throws(TransportError) in throw .network("offline")
    }
    var openGift: @Sendable (OpenGiftRequest) async throws(TransportError) -> OpenGiftResponse = {
        (_) async throws(TransportError) in throw .network("offline")
    }
    var claimBonus: @Sendable (ClaimBonusRequest) async throws(TransportError) -> ClaimBonusResponse = {
        (_) async throws(TransportError) in throw .network("offline")
    }
    var earn: @Sendable (EarnRequest) async throws(TransportError) -> EarnResponse = {
        (_) async throws(TransportError) in throw .network("offline")
    }
    /// The balance and the wallet's entries after an entry id (from the first with nil), oldest first.
    var coins: @Sendable (_ after: String?) async throws(TransportError) -> CoinsResponse = {
        (_) async throws(TransportError) in throw .network("offline")
    }

    static func live(_ api: APIClient) -> ShopSync {
        ShopSync(
            fetch: api.shop, order: api.placeOrder, wish: api.setWish, inks: api.listInks, openGift: api.openGift,
            claimBonus: api.claimBonus, earn: api.earnCoins, coins: api.getCoins)
    }
}
