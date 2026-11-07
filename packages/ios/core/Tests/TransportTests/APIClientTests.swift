import Foundation
import Testing
import Wire

@testable import Transport

@Suite struct APIClientTests {
  /// Answers every request with `status` and `body`, and keeps what was asked.
  final class Server: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [HTTPRequest] = []
    let status: Int
    let body: String

    init(status: Int = 200, body: String = "{}") {
      self.status = status
      self.body = body
    }

    var requests: [HTTPRequest] { lock.withLock { seen } }

    var http: HTTPService {
      HTTPService { [self] request in
        lock.withLock { seen.append(request) }
        return HTTPResponse(status: status, body: Data(body.utf8))
      }
    }
  }

  static func client(_ server: Server, token: String? = "tok") -> APIClient {
    APIClient.live(http: server.http, token: { token })
  }

  @Test func theChallengeIsAskedWithoutAToken() async throws {
    let nonce = String(repeating: "a", count: 43)
    let server = Server(body: #"{"nonce":"\#(nonce)","expiresAt":5}"#)
    let response = try await Self.client(server, token: nil).authChallenge()
    #expect(response.expiresAt == 5)
    let request = try #require(server.requests.first)
    #expect(request.method == .post)
    #expect(request.path == "/v1/auth/challenge")
    #expect(request.headers["Authorization"] == nil)
  }

  @Test func signedRoutesCarryTheBearerToken() async throws {
    let server = Server(status: 204, body: "")
    try await Self.client(server).unpair()
    let request = try #require(server.requests.first)
    #expect(request.method == .delete)
    #expect(request.path == "/v1/pair")
    #expect(request.headers["Authorization"] == "Bearer tok")
  }

  @Test func theGuessCatalogRevalidatesWhatTheCacheHolds() async throws {
    let server = Server(body: #"{"version":"v2","questions":[]}"#)
    let catalog = try await Self.client(server, token: nil).guessCatalog()
    #expect(catalog.version == "v2")
    let request = try #require(server.requests.first)
    #expect(request.path == "/v1/guess/catalog")
    #expect(request.headers["Cache-Control"] == "no-cache")
  }

  @Test func aSignedRouteWithoutATokenNeverLeavesTheDevice() async {
    let server = Server(status: 204, body: "")
    await #expect(throws: TransportError.api(.unauthorized)) {
      try await Self.client(server, token: nil).signOut()
    }
    #expect(server.requests.isEmpty)
  }

  @Test func claimingSendsTheCodeAsJSON() async throws {
    let server = Server(body: #"{"pairId":"p1"}"#)
    let response = try await Self.client(server).claimInvite(
      ClaimInviteRequest(code: InviteCode("ABC")))
    #expect(response == ClaimInviteResponse(pairId: PairId("p1")))
    let request = try #require(server.requests.first)
    #expect(request.path == "/v1/invites/claim")
    #expect(request.headers["Content-Type"] == "application/json")
    #expect(request.body.map { String(decoding: $0, as: UTF8.self) } == #"{"code":"ABC"}"#)
  }

  @Test func historyAsksAfterTheLastSeqItHolds() async throws {
    let server = Server(body: #"{"notes":[]}"#)
    _ = try await Self.client(server).listNotes(nil)
    _ = try await Self.client(server).listNotes(7)
    #expect(server.requests.map(\.path) == ["/v1/notes", "/v1/notes?after=7"])
  }

  @Test func activityPagesAskBeforeTheLastCursor() async throws {
    let server = Server(body: #"{"items":[],"unread":0}"#)
    _ = try await Self.client(server).listActivity(nil)
    _ = try await Self.client(server).listActivity("0001700000100000~note:note-1")
    #expect(
      server.requests.map(\.path) == [
        "/v1/activity", "/v1/activity?before=0001700000100000~note:note-1",
      ])
  }

  @Test func markingActivityReadSendsTheCursorAndAnswersTheCount() async throws {
    let server = Server(body: #"{"unread":2}"#)
    let response = try await Self.client(server).markActivityRead(
      MarkActivityReadRequest(upTo: "0001700000100000~note:note-1"))
    #expect(response.unread == 2)
    let request = try #require(server.requests.first)
    #expect(request.method == .post)
    #expect(request.path == "/v1/activity/read")
    #expect(
      request.body.map { String(decoding: $0, as: UTF8.self) }
        == #"{"upTo":"0001700000100000~note:note-1"}"#)
  }

  @Test func flagsAreReadWithTheTokenAndDecoded() async throws {
    let server = Server(body: #"{"flags":[{"key":"home-direction","variant":"window-seat"}]}"#)
    let response = try await Self.client(server).flags()
    #expect(response.flags == [FlagAssignment(key: "home-direction", variant: "window-seat")])
    let request = try #require(server.requests.first)
    #expect(request.method == .get)
    #expect(request.path == "/v1/flags")
    #expect(request.headers["Authorization"] == "Bearer tok")
  }

  @Test func flagsWithoutATokenNeverLeaveTheDevice() async {
    let server = Server()
    await #expect(throws: TransportError.api(.unauthorized)) {
      _ = try await Self.client(server, token: nil).flags()
    }
    #expect(server.requests.isEmpty)
  }

  @Test func eventsGoUpAsNamesWithTheirDetailAndNothingElse() async throws {
    let server = Server(status: 204, body: "")
    try await Self.client(server).reportEvents([
      ClientEvent(.appOpened), ClientEvent(.shopItemBought, detail: "treat-fish", value: 3),
    ])
    let request = try #require(server.requests.first)
    #expect(request.method == .post)
    #expect(request.path == "/v1/events")
    #expect(request.headers["Authorization"] == "Bearer tok")
    let body = try #require(request.body)
    let sent = try #require(try JSONSerialization.jsonObject(with: body) as? NSDictionary)
    let expected: NSDictionary = [
      "events": [
        ["name": "AppOpened"], ["name": "ShopItemBought", "detail": "treat-fish", "value": 3],
      ]
    ]
    #expect(sent == expected)
  }

  @Test func imagesGoUpWithTheirOwnTypeAndComeBackAsBytes() async throws {
    let up = Server(body: #"{"image":"couples/p1/a.png"}"#)
    _ = try await Self.client(up).uploadImage(Data([1, 2, 3]))
    let request = try #require(up.requests.first)
    #expect(request.headers["Content-Type"] == "image/png")
    #expect(request.body == Data([1, 2, 3]))

    let photo = Server(body: #"{"image":"couples/p1/b.jpg"}"#)
    _ = try await Self.client(photo).uploadImage(Data([0xFF, 0xD8, 0xFF, 0xE0]))
    #expect(photo.requests.first?.headers["Content-Type"] == "image/jpeg")

    let down = Server(body: "bytes")
    let bytes = try await Self.client(down).downloadImage(MediaKey("couples/p1/a.png"))
    #expect(bytes == Data("bytes".utf8))
    #expect(down.requests.first?.path == "/v1/media/couples/p1/a.png")
  }

  @Test func inksAndCoinsAreReadWithTheToken() async throws {
    let inks = Server(
      body:
        ##"{"inks":[{"id":"ink-graphite","name":"Graphite","light":"#2B2B2E","dark":"#ECEAE4","price":0}],"owned":["ink-graphite"]}"##
    )
    let catalog = try await Self.client(inks).listInks()
    #expect(catalog.owned == [InkId.free])
    #expect(catalog.inks.first?.light == "#2B2B2E")
    #expect(inks.requests.first?.path == "/v1/inks")
    #expect(inks.requests.first?.headers["Authorization"] == "Bearer tok")

    let coins = Server(body: #"{"balance":140,"entries":[]}"#)
    #expect(try await Self.client(coins).getCoins(nil).balance == 140)
    #expect(coins.requests.first?.method == .get)
    #expect(coins.requests.first?.path == "/v1/coins")
    _ = try await Self.client(coins).getCoins("spend:k1")
    #expect(coins.requests.last?.path == "/v1/coins?after=spend%3Ak1")
  }

  @Test func buyingSendsTheKeyAndTheInk() async throws {
    let server = Server(
      body:
        #"{"entry":{"id":"buy:k1","kind":"buy","amount":-60,"ref":"ink-rose","at":5},"balance":80,"granted":["ink-rose"],"owned":["ink-graphite","ink-rose"]}"#
    )
    let response = try await Self.client(server).buyItem(
      BuyRequest(id: IdempotencyKey("k1"), item: InkId("ink-rose")))
    #expect(response.balance == 80)
    #expect(response.owned == [InkId.free, InkId("ink-rose")])
    let request = try #require(server.requests.first)
    #expect(request.method == .post)
    #expect(request.path == "/v1/shop/buy")
    let body = try #require(request.body)
    let sent = try #require(try JSONSerialization.jsonObject(with: body) as? NSDictionary)
    #expect(sent == ["id": "k1", "item": "ink-rose"])
  }

  @Test func aShortBalanceSaysHowShort() async {
    let server = Server(status: 402, body: #"{"_tag":"NotEnoughCoins","needed":60,"have":25}"#)
    await #expect(throws: TransportError.api(.notEnoughCoins(needed: 60, have: 25))) {
      _ = try await Self.client(server).buyItem(
        BuyRequest(id: IdempotencyKey("k1"), item: InkId("ink-rose")))
    }
  }

  @Test func contractErrorsKeepTheirName() async {
    let server = Server(status: 409, body: #"{"_tag":"AlreadyPaired"}"#)
    await #expect(throws: TransportError.api(.alreadyPaired)) {
      try await Self.client(server).claimInvite(ClaimInviteRequest(code: InviteCode("ABC")))
    }
  }

  @Test func anOrderSendsThePhonesClockForTheDaysDeal() async throws {
    let server = Server(
      body:
        #"{"entry":{"id":"spend:k1","kind":"spend","amount":-45,"ref":"yarn","at":5},"shop":{"balance":515,"inks":["ink-graphite"],"items":["lamp","rug","yarn"],"wishlist":[],"bonuses":[]}}"#
    )
    let response = try await Self.client(server).placeOrder(
      OrderRequest(
        id: IdempotencyKey("k1"), offer: .item(RoomItemId("yarn")), utcOffsetSeconds: 3600))
    #expect(response.shop.balance == 515)
    let body = try #require(server.requests.first?.body)
    let sent = try #require(try JSONSerialization.jsonObject(with: body) as? NSDictionary)
    #expect(
      sent == ["id": "k1", "offer": ["_tag": "Item", "item": "yarn"], "utcOffsetSeconds": 3600])
  }

  @Test func theGiftBonusAndEarnsGoToTheirRoutes() async throws {
    let gift = Server(
      body:
        #"{"entry":{"id":"gift:2026-11-05","kind":"gift","amount":0,"ref":"yarn","at":5},"reward":{"_tag":"Item","item":"yarn"},"shop":{"balance":560,"inks":["ink-graphite"],"items":["lamp","rug","yarn"],"wishlist":[],"giftDay":"2026-11-05","bonuses":[]}}"#
    )
    let opened = try await Self.client(gift).openGift(OpenGiftRequest())
    #expect(opened.reward == .item(RoomItemId("yarn")))
    #expect(opened.shop.giftDay == "2026-11-05")
    #expect(gift.requests.first?.path == "/v1/shop/gift")

    let bonus = Server(
      status: 409, body: #"{"_tag":"CollectionIncomplete","collection":"cozy-autumn"}"#)
    await #expect(throws: TransportError.api(.collectionIncomplete(collection: "cozy-autumn"))) {
      _ = try await Self.client(bonus).claimBonus(ClaimBonusRequest(collection: "cozy-autumn"))
    }
    #expect(bonus.requests.first?.path == "/v1/shop/bonus")

    let earn = Server(body: #"{"balance":575}"#)
    let earned = try await Self.client(earn).earnCoins(
      EarnRequest(event: .listTicked(item: "item-1"), utcOffsetSeconds: 0))
    #expect(earned.entry == nil)
    #expect(earn.requests.first?.path == "/v1/coins/earn")
  }

  @Test func aCheckInIsPutAndAnsweredAsStored() async throws {
    let server = Server(
      body: #"{"user":"u1","mood":"busy","note":"till six","at":5}"#)
    let stored = try await Self.client(server).setMood(
      SetMoodRequest(mood: .busy, note: " till six "))
    #expect(stored == PartnerCheckIn(user: UserId("u1"), mood: .busy, note: "till six", at: 5))
    let request = try #require(server.requests.first)
    #expect(request.method == .put)
    #expect(request.path == "/v1/mood")
    let body = try #require(request.body)
    let sent = try #require(try JSONSerialization.jsonObject(with: body) as? NSDictionary)
    #expect(sent == ["mood": "busy", "note": " till six "])

    let long = Server(status: 400, body: #"{"_tag":"InvalidRequest"}"#)
    await #expect(throws: TransportError.api(.invalidRequest)) {
      _ = try await Self.client(long).setMood(SetMoodRequest(mood: .happy))
    }
  }

  @Test func thePairCarriesBothCheckInsAndAPairFromBeforeMoodsHasNone() async throws {
    let server = Server(
      body:
        #"{"pairId":"p1","members":["u1","u2"],"moods":[{"user":"u2","mood":"sleepy","at":5},{"user":"u1","mood":"grumpy","at":6}]}"#
    )
    let pair = try await Self.client(server).pair()
    #expect(pair.moods == [PartnerCheckIn(user: UserId("u2"), mood: .sleepy, at: 5)])
    let older = try JSONDecoder().decode(
      PairResponse.self, from: Data(#"{"pairId":"p1","members":["u1","u2"]}"#.utf8))
    #expect(older.moods == [])
  }

  @Test func aShopFromBeforeBonusesReadsWithNone() throws {
    let shop = try JSONDecoder().decode(
      ShopResponse.self,
      from: Data(
        #"{"balance":0,"inks":["ink-graphite"],"items":["lamp","rug"],"wishlist":[]}"#.utf8))
    #expect(shop.bonuses == [])
    #expect(shop.giftDay == nil)
  }

  @Test func aTryAndAHintGoToTheRiddlesOwnPath() async throws {
    let id = RiddleId("00000000-0000-4000-8000-0000000000d1")
    let key = IdempotencyKey("00000000-0000-4000-8000-0000000000aa")
    let tried = Server(
      body:
        ##"{"riddle":{"at":1700000000000,"compact":{"strokes":[{"color":"#2A1A1C","points":[10,20,30,40],"width":3}],"version":1},"drawer":"user-alice","hints":2,"id":"00000000-0000-4000-8000-0000000000d1","image":"pairs/pair-1/notes/riddle-1.png","removed":[3,8],"revealed":[{"index":6,"letter":"o"}],"shape":[5,4],"state":{"_tag":"Solved","at":1700000090000},"tiles":["e","o","r","x","p","t","n","h","q","l","o","z"],"tries":4,"word":"north pole"},"right":true}"##
    )
    let response = try await Self.client(tried).guessRiddle(id, key, " Cat ")
    #expect(response.right)
    let request = try #require(tried.requests.first)
    #expect(request.method == .post)
    #expect(request.path == "/v1/riddles/\(id.rawValue)/guess")
    let body = try #require(request.body)
    let sent = try #require(try JSONSerialization.jsonObject(with: body) as? NSDictionary)
    #expect(sent == ["key": key.rawValue, "guess": " Cat "])

    let hinted = Server(
      body:
        ##"{"at":1700000000000,"compact":{"strokes":[{"color":"#2A1A1C","points":[10,20,30,40],"width":3}],"version":1},"drawer":"user-alice","hints":2,"id":"00000000-0000-4000-8000-0000000000d1","image":"pairs/pair-1/notes/riddle-1.png","removed":[3,8],"revealed":[{"index":6,"letter":"o"}],"shape":[5,4],"state":{"_tag":"Solved","at":1700000090000},"tiles":["e","o","r","x","p","t","n","h","q","l","o","z"],"tries":4,"word":"north pole"}"##
    )
    _ = try await Self.client(hinted).hintRiddle(id)
    let hint = try #require(hinted.requests.first)
    #expect(hint.path == "/v1/riddles/\(id.rawValue)/hint")
    #expect(hint.body == nil)
  }
}
