import Foundation
import Wire

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
  public var plus: @Sendable () async throws(TransportError) -> PlusResponse
  public var subscribePlus:
    @Sendable (SubscribeRequest) async throws(TransportError) -> PlusResponse
  public var mockPlus: @Sendable (MockPlusRequest) async throws(TransportError) -> PlusResponse
  public var openParcel:
    @Sendable (OpenParcelRequest) async throws(TransportError) -> OpenParcelResponse

  public init(
    purchase:
      @escaping @Sendable (PurchaseRequest) async throws(TransportError) ->
      PurchaseResponse,
    mockPurchase:
      @escaping @Sendable (MockPurchaseRequest) async throws(TransportError) ->
      PurchaseResponse,
    stamps: @escaping @Sendable () async throws(TransportError) -> StampsResponse,
    plus: @escaping @Sendable () async throws(TransportError) -> PlusResponse = {
      () async throws(TransportError) in throw .api(.notFound)
    },
    subscribePlus:
      @escaping @Sendable (SubscribeRequest) async throws(TransportError) -> PlusResponse = {
        (_) async throws(TransportError) in throw .api(.notFound)
      },
    mockPlus:
      @escaping @Sendable (MockPlusRequest) async throws(TransportError) -> PlusResponse = {
        (_) async throws(TransportError) in throw .api(.notFound)
      },
    openParcel:
      @escaping @Sendable (OpenParcelRequest) async throws(TransportError) ->
      OpenParcelResponse = { (_) async throws(TransportError) in throw .api(.notFound) }
  ) {
    self.purchase = purchase
    self.mockPurchase = mockPurchase
    self.stamps = stamps
    self.plus = plus
    self.subscribePlus = subscribePlus
    self.mockPlus = mockPlus
    self.openParcel = openParcel
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

    @Sendable func post<Body: Encodable & Sendable, Answer: Decodable & Sendable>(
      _ route: Route, _ body: Body, as answer: Answer.Type = PurchaseResponse.self
    ) async throws(TransportError) -> Answer {
      let request = try HTTPRequest.json(
        route.method, path: route.path, body: body, headers: try await identity())
      return try await http.perform(request, as: answer)
    }

    return PurchasesClient(
      purchase: { (body) async throws(TransportError) in try await post(Routes.purchase, body) },
      mockPurchase: { (body) async throws(TransportError) in
        try await post(Routes.mockPurchase, body)
      },
      stamps: { () async throws(TransportError) in
        try await http.perform(
          HTTPRequest(
            method: Routes.getPurchases.method, path: Routes.getPurchases.path,
            headers: try await identity()),
          as: StampsResponse.self)
      },
      plus: { () async throws(TransportError) in
        try await http.perform(
          HTTPRequest(
            method: Routes.getPlus.method, path: Routes.getPlus.path,
            headers: try await identity()),
          as: PlusResponse.self)
      },
      subscribePlus: { (body) async throws(TransportError) in
        try await post(Routes.subscribePlus, body, as: PlusResponse.self)
      },
      mockPlus: { (body) async throws(TransportError) in
        try await post(Routes.mockPlus, body, as: PlusResponse.self)
      },
      openParcel: { (body) async throws(TransportError) in
        try await post(Routes.openParcel, body, as: OpenParcelResponse.self)
      })
  }
}
