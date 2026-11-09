import Transport
import Wire

/// The pair's shop and wallet on the server: what it has, and every request that changes it. The
/// server prices every order and keeps the only balance; the app's prices are only shown.
public struct ShopClient: Sendable {
  public var fetch: @Sendable () async throws(TransportError) -> ShopResponse
  public var order: @Sendable (OrderRequest) async throws(TransportError) -> OrderResponse
  public var wish: @Sendable (WishRequest) async throws(TransportError) -> ShopResponse
  public var inks: @Sendable () async throws(TransportError) -> InksResponse
  public var openGift: @Sendable (OpenGiftRequest) async throws(TransportError) -> OpenGiftResponse
  public var claimBonus:
    @Sendable (ClaimBonusRequest) async throws(TransportError) -> ClaimBonusResponse
  public var earn: @Sendable (EarnRequest) async throws(TransportError) -> EarnResponse
  /// The balance and the wallet's entries after an entry id (nil: from the first), oldest first.
  public var coins: @Sendable (_ after: String?) async throws(TransportError) -> CoinsResponse

  public init(
    fetch: @escaping @Sendable () async throws(TransportError) -> ShopResponse,
    order: @escaping @Sendable (OrderRequest) async throws(TransportError) -> OrderResponse,
    wish: @escaping @Sendable (WishRequest) async throws(TransportError) -> ShopResponse,
    inks: @escaping @Sendable () async throws(TransportError) -> InksResponse = {
      () async throws(TransportError) in throw .network("offline")
    },
    openGift:
      @escaping @Sendable (OpenGiftRequest) async throws(TransportError) ->
      OpenGiftResponse = { (_) async throws(TransportError) in throw .network("offline") },
    claimBonus:
      @escaping @Sendable (ClaimBonusRequest) async throws(TransportError) ->
      ClaimBonusResponse = { (_) async throws(TransportError) in throw .network("offline") },
    earn: @escaping @Sendable (EarnRequest) async throws(TransportError) -> EarnResponse = {
      (_) async throws(TransportError) in throw .network("offline")
    },
    coins: @escaping @Sendable (_ after: String?) async throws(TransportError) -> CoinsResponse = {
      (_) async throws(TransportError) in throw .network("offline")
    }
  ) {
    self.fetch = fetch
    self.order = order
    self.wish = wish
    self.inks = inks
    self.openGift = openGift
    self.claimBonus = claimBonus
    self.earn = earn
    self.coins = coins
  }

  public static func live(_ api: APIClient) -> ShopClient {
    ShopClient(
      fetch: api.shop, order: api.placeOrder, wish: api.setWish, inks: api.listInks,
      openGift: api.openGift, claimBonus: api.claimBonus, earn: api.earnCoins, coins: api.getCoins)
  }
}
