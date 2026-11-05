import Transport
import Wire

/// The pair's gift wishes in its room. Every call answers the gifts as this account may see them: its own plans only.
struct GiftSync: Sendable {
    var fetch: @Sendable () async throws(TransportError) -> GiftsResponse
    var saveWish: @Sendable (SaveGiftWishRequest) async throws(TransportError) -> GiftsResponse
    var deleteWish: @Sendable (DeleteGiftWishRequest) async throws(TransportError) -> GiftsResponse
    var setPlan: @Sendable (SetGiftPlanRequest) async throws(TransportError) -> GiftsResponse
    var markReceived: @Sendable (MarkGiftReceivedRequest) async throws(TransportError) -> GiftsResponse
    var saveLoves: @Sendable (SaveLovesRequest) async throws(TransportError) -> GiftsResponse

    static func live(_ api: APIClient) -> GiftSync {
        GiftSync(fetch: api.gifts, saveWish: api.saveGiftWish, deleteWish: api.deleteGiftWish,
                 setPlan: api.setGiftPlan, markReceived: api.markGiftReceived, saveLoves: api.saveLoves)
    }
}
