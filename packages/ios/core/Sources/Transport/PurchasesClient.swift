import Foundation
import Wire

/// The purchase routes: credit a StoreKit transaction, credit or refund a mock one (dev server
/// only), and read the pair's stamp ledger. Tests pass fakes.
public struct PurchasesClient: Sendable {
  /// Who the caller is on these routes: a signed-in session, or (dev server only) a demo room.
  public enum Caller: Sendable {
    case session(@Sendable () async -> String?)
    case demoRoom(@Sendable () -> String?)
  }

  public var purchase: @Sendable (PurchaseRequest) async throws(TransportError) -> PurchaseResponse
  public var mockPurchase:
    @Sendable (MockPurchaseRequest) async throws(TransportError) -> PurchaseResponse
  public var stamps: @Sendable () async throws(TransportError) -> StampsResponse

  public init(
    purchase:
      @escaping @Sendable (PurchaseRequest) async throws(TransportError) ->
      PurchaseResponse,
    mockPurchase:
      @escaping @Sendable (MockPurchaseRequest) async throws(TransportError) ->
      PurchaseResponse,
    stamps: @escaping @Sendable () async throws(TransportError) -> StampsResponse
  ) {
    self.purchase = purchase
    self.mockPurchase = mockPurchase
    self.stamps = stamps
  }

  public static func live(http: HTTPService, caller: Caller) -> PurchasesClient {
    @Sendable func identity() async throws(TransportError) -> [String: String] {
      switch caller {
      case .session(let token):
        guard let token = await token() else { throw .api(.unauthorized) }
        return [Routes.authorizationHeader: Routes.bearerPrefix + token]
      case .demoRoom(let room):
        guard let room = room(), !room.isEmpty else { throw .api(.unauthorized) }
        return [Routes.demoRoomHeader: room]
      }
    }

    @Sendable func post<Body: Encodable & Sendable>(_ route: Route, _ body: Body)
      async throws(TransportError) -> PurchaseResponse
    {
      let request = try HTTPRequest.json(
        route.method, path: route.path, body: body, headers: try await identity())
      return try await http.perform(request, as: PurchaseResponse.self)
    }

    return PurchasesClient(
      purchase: { (body) async throws(TransportError) in try await post(Routes.purchase, body) },
      mockPurchase: { (body) async throws(TransportError) in
        try await post(Routes.mockPurchase, body)
      },
      stamps: { () async throws(TransportError) in
        try await http.perform(
          HTTPRequest(
            method: Routes.getStamps.method, path: Routes.getStamps.path,
            headers: try await identity()),
          as: StampsResponse.self)
      })
  }
}
