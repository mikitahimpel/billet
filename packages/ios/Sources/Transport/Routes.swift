import Foundation

/// A route of the API: the method and path the contracts name for it.
public struct Route: Equatable, Sendable {
  public let method: HTTPMethod
  public let path: String

  public init(_ method: HTTPMethod, _ path: String) {
    self.method = method
    self.path = path
  }
}

/// Every route of the API, mirroring `routes` in `packages/contracts/http-api/src/routes.ts`.
/// `RoutesContractTests` reads that file, so a route changed there fails here until this follows.
public enum Routes {
  public static let authChallenge = Route(.post, "/v1/auth/challenge")
  public static let authAnonymous = Route(.post, "/v1/auth/anonymous")
  public static let authApple = Route(.post, "/v1/auth/apple")
  public static let authAppleLink = Route(.post, "/v1/auth/apple/link")
  public static let getAccount = Route(.get, "/v1/account")
  public static let deleteAccount = Route(.delete, "/v1/account")
  public static let authSignOut = Route(.post, "/v1/auth/sign-out")
  public static let registerPushToken = Route(.put, "/v1/devices/current/push-token")
  public static let createInvite = Route(.post, "/v1/invites")
  public static let claimInvite = Route(.post, "/v1/invites/claim")
  public static let unpair = Route(.delete, "/v1/pair")
  public static let uploadImage = Route(.post, "/v1/media")
  public static let sendNote = Route(.post, "/v1/notes")
  public static let listNotes = Route(.get, "/v1/notes")
  public static let getFlags = Route(.get, "/v1/flags")
  public static let getStatus = Route(.get, "/v1/status")
  public static let reportEvents = Route(.post, "/v1/events")
  public static let purchase = Route(.post, "/v1/purchases")
  /// Dev server only: the mock store's purchases and refunds.
  public static let mockPurchase = Route(.post, "/v1/purchases/mock")
  public static let getStamps = Route(.get, "/v1/stamps")
  /// Called by Apple, never by the app. Mirrored so the contract test covers every route.
  public static let appStoreNotifications = Route(.post, "/v1/appstore/notifications")

  /// `GET /v1/media/*`: the media key is the rest of the path.
  public static let downloadImagePrefix = "/v1/media/"

  public static func downloadImage(key: String) -> Route {
    Route(.get, downloadImagePrefix + key)
  }

  /// The WebSocket route, `socketRoute` in `realtime/src/socket-route.ts`.
  public static let socket = Route(.get, "/v1/socket")

  /// The header every route but the two sign-in ones is called with, and its value's prefix.
  public static let authorizationHeader = "Authorization"
  public static let bearerPrefix = "Bearer "

  /// What the app says about its own build on every request, `clientHeaders` in `routes.ts`.
  /// See ``ClientInfo``.
  public static let appVersionHeader = "X-Billet-App-Version"
  public static let osHeader = "X-Billet-OS"
  /// Dev server only: names the demo room on the purchase routes when there is no session.
  public static let demoRoomHeader = "X-Billet-Demo-Room"
}

extension URLRequest {
  /// The upgrade request for the signed-in socket, at `/v1/socket` on `baseURL`'s host over
  /// `wss`, or `ws` when the base is plain `http` (a local dev server).
  public static func socket(baseURL: URL, token: String) -> URLRequest? {
    guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      return nil
    }
    switch parts.scheme {
    case "https": parts.scheme = "wss"
    case "http": parts.scheme = "ws"
    default: return nil
    }
    parts.path = Routes.socket.path
    guard let url = parts.url else { return nil }
    var request = URLRequest(url: url)
    request.setValue(Routes.bearerPrefix + token, forHTTPHeaderField: Routes.authorizationHeader)
    return request
  }
}
