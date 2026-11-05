import Transport
import Wire

/// The pair's shop on the server: what it has, and the orders and wishes that change it. The server prices every
/// order; the app's prices are only shown.
struct ShopSync: Sendable {
    var fetch: @Sendable () async throws(TransportError) -> ShopResponse
    var order: @Sendable (OrderRequest) async throws(TransportError) -> OrderResponse
    var wish: @Sendable (WishRequest) async throws(TransportError) -> ShopResponse

    static func live(_ api: APIClient) -> ShopSync {
        ShopSync(fetch: api.shop, order: api.placeOrder, wish: api.setWish)
    }
}
