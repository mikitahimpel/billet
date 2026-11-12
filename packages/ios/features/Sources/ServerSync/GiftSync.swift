import Transport
import Wire

/// The pair's gift wishes in its room. Every call answers the gifts as this account may see them: its own plans only.
public struct GiftSync: Sendable {
  public var fetch: @Sendable () async throws(TransportError) -> GiftsResponse
  public var saveWish: @Sendable (SaveGiftWishRequest) async throws(TransportError) -> GiftsResponse
  public var deleteWish:
    @Sendable (DeleteGiftWishRequest) async throws(TransportError) -> GiftsResponse
  public var setPlan: @Sendable (SetGiftPlanRequest) async throws(TransportError) -> GiftsResponse
  public var markReceived:
    @Sendable (MarkGiftReceivedRequest) async throws(TransportError) -> GiftsResponse
  public var saveLoves: @Sendable (SaveLovesRequest) async throws(TransportError) -> GiftsResponse

  public init(
    fetch: @escaping @Sendable () async throws(TransportError) -> GiftsResponse,
    saveWish:
      @escaping @Sendable (SaveGiftWishRequest) async throws(TransportError) -> GiftsResponse,
    deleteWish:
      @escaping @Sendable (DeleteGiftWishRequest) async throws(TransportError) -> GiftsResponse,
    setPlan: @escaping @Sendable (SetGiftPlanRequest) async throws(TransportError) -> GiftsResponse,
    markReceived:
      @escaping @Sendable (MarkGiftReceivedRequest) async throws(TransportError) -> GiftsResponse,
    saveLoves: @escaping @Sendable (SaveLovesRequest) async throws(TransportError) -> GiftsResponse
  ) {
    self.fetch = fetch
    self.saveWish = saveWish
    self.deleteWish = deleteWish
    self.setPlan = setPlan
    self.markReceived = markReceived
    self.saveLoves = saveLoves
  }

  public static func live(_ api: APIClient) -> GiftSync {
    GiftSync(
      fetch: api.gifts, saveWish: api.saveGiftWish, deleteWish: api.deleteGiftWish,
      setPlan: api.setGiftPlan, markReceived: api.markGiftReceived, saveLoves: api.saveLoves)
  }
}
