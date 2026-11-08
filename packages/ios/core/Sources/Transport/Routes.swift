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
  public static let blockPartner = Route(.post, "/v1/pair/block")
  public static let reportPartner = Route(.post, "/v1/pair/report")
  public static let getPair = Route(.get, "/v1/pair")
  public static let setMood = Route(.put, "/v1/mood")
  /// The pair's love streak; `POST` a day the caller did something together, or a restore.
  public static let getStreak = Route(.get, "/v1/streak")
  public static let recordStreakDay = Route(.post, "/v1/streak/days")
  public static let restoreStreak = Route(.post, "/v1/streak/restore")
  public static let uploadImage = Route(.post, "/v1/media")
  public static let sendNote = Route(.post, "/v1/notes")
  public static let listNotes = Route(.get, "/v1/notes")
  /// Sets or takes back this user's reaction to one of the partner's photos.
  public static let react = Route(.put, "/v1/reactions")
  public static let listReactions = Route(.get, "/v1/reactions")
  public static let listInks = Route(.get, "/v1/inks")
  public static let getCoins = Route(.get, "/v1/coins")
  public static let buyItem = Route(.post, "/v1/shop/buy")
  /// The pair's balance, inks, room pieces and wishlist, and the orders and wishes that change it.
  public static let getShop = Route(.get, "/v1/shop")
  public static let placeOrder = Route(.post, "/v1/shop/orders")
  public static let setWish = Route(.put, "/v1/shop/wishlist")
  public static let openGift = Route(.post, "/v1/shop/gift")
  public static let claimBonus = Route(.post, "/v1/shop/bonus")
  public static let earnCoins = Route(.post, "/v1/coins/earn")
  /// The pair's gift wishes, the caller's own gift plans and both partners' "What I love". Every
  /// change answers the same view.
  public static let getGifts = Route(.get, "/v1/gifts")
  public static let saveGiftWish = Route(.put, "/v1/gifts/wishes")
  public static let deleteGiftWish = Route(.delete, "/v1/gifts/wishes")
  public static let setGiftPlan = Route(.put, "/v1/gifts/plans")
  public static let markGiftReceived = Route(.put, "/v1/gifts/received")
  public static let saveLoves = Route(.put, "/v1/gifts/loves")
  /// The pair's shared lists. A change answers the lists after it.
  public static let getLists = Route(.get, "/v1/lists")
  public static let changeList = Route(.post, "/v1/lists")
  /// Films and shows on TMDB, through the Worker; `getTitle`'s `:kind` and `:tmdb` name one.
  public static let searchTitles = Route(.get, "/v1/titles/search")
  public static let getTitle = Route(.get, "/v1/titles/:kind/:tmdb")
  /// Films and shows like the ones in `ids` (`movie:329865,tv:95396`), for Pick tonight's deck.
  public static let titleRecommendations = Route(.get, "/v1/titles/recommendations")
  /// The pair's Pick tonight session; a swipe answers the session after it.
  public static let getPickTonight = Route(.get, "/v1/pick-tonight")
  public static let swipePickTonight = Route(.post, "/v1/pick-tonight/swipes")
  /// Today's Who knows who round; an answer answers the round after it. The catalog needs no
  /// session.
  public static let getGuess = Route(.get, "/v1/guess")
  public static let answerGuess = Route(.post, "/v1/guess/answers")
  public static let getGuessCatalog = Route(.get, "/v1/guess/catalog")
  /// The pair's draw-guess riddles; `:id` names one.
  public static let getRiddles = Route(.get, "/v1/riddles")
  public static let sendRiddle = Route(.post, "/v1/riddles")
  public static let guessRiddle = Route(.post, "/v1/riddles/:id/guess")
  public static let hintRiddle = Route(.post, "/v1/riddles/:id/hint")
  public static let giveUpRiddle = Route(.post, "/v1/riddles/:id/give-up")
  public static let getFlags = Route(.get, "/v1/flags")
  public static let getStatus = Route(.get, "/v1/status")
  public static let getDateCatalog = Route(.get, "/v1/dates/catalog")
  /// The shop's active items. Needs no session.
  public static let getShopCatalog = Route(.get, "/v1/shop/catalog")
  /// An uploaded shop picture: `shopArtPrefix` and its key.
  public static let shopArtPrefix = "/v1/shop/art/"
  public static let getShopArt = Route(.get, shopArtPrefix + "*")
  public static let reportEvents = Route(.post, "/v1/events")
  public static let getOnboarding = Route(.get, "/v1/onboarding")
  public static let saveOnboardingAnswer = Route(.post, "/v1/onboarding/answers")
  /// The couple's cat: its profile, temper and needs; `PUT` adopts or renames it.
  public static let getCat = Route(.get, "/v1/cat")
  public static let saveCat = Route(.put, "/v1/cat")
  public static let listCatJournal = Route(.get, "/v1/cat/journal")
  public static let recordCatEvent = Route(.post, "/v1/cat/events")
  /// The pair's Inbox, newest first, and the caller's read mark.
  public static let listActivity = Route(.get, "/v1/activity")
  public static let markActivityRead = Route(.post, "/v1/activity/read")
  public static let purchase = Route(.post, "/v1/purchases")
  /// Dev server only: the mock store's purchases and refunds.
  public static let mockPurchase = Route(.post, "/v1/purchases/mock")
  /// Dev server only: pairs the signed-in, unpaired caller with a bot partner.
  public static let createDemoPartner = Route(.post, "/v1/dev/demo-partner")
  /// Dev server only: whether the caller is paired with their bot partner. A 404 means no dev tools.
  public static let getDemoPartner = Route(.get, "/v1/dev/demo-partner")
  /// Dev server only: unpairs the caller from their bot partner and deletes it.
  public static let removeDemoPartner = Route(.delete, "/v1/dev/demo-partner")
  public static let getPurchases = Route(.get, "/v1/purchases")
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
