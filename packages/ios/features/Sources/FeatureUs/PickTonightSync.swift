import Transport
import Wire

/// The pair's Pick tonight session in its room. Every call answers the session as this user sees it after it.
public struct PickTonightSync: Sendable {
  var fetch: @Sendable () async throws(TransportError) -> PickTonightResponse
  var swipe: @Sendable (PickSwipeRequest) async throws(TransportError) -> PickTonightResponse

  public init(
    fetch: @escaping @Sendable () async throws(TransportError) -> PickTonightResponse,
    swipe:
      @escaping @Sendable (PickSwipeRequest) async throws(TransportError) -> PickTonightResponse
  ) {
    self.fetch = fetch
    self.swipe = swipe
  }

  public static func live(_ api: APIClient) -> PickTonightSync {
    PickTonightSync(fetch: api.pickTonight, swipe: api.swipePickTonight)
  }
}
