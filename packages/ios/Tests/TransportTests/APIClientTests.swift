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

  @Test func eventsGoUpAsNamesAndNothingElse() async throws {
    let server = Server(status: 204, body: "")
    try await Self.client(server).reportEvents([.appOpened, .widgetAdded])
    let request = try #require(server.requests.first)
    #expect(request.method == .post)
    #expect(request.path == "/v1/events")
    #expect(request.headers["Authorization"] == "Bearer tok")
    #expect(
      request.body.map { String(decoding: $0, as: UTF8.self) }
        == #"{"events":["AppOpened","WidgetAdded"]}"#)
  }

  @Test func imagesGoUpAsPNGAndComeBackAsBytes() async throws {
    let up = Server(body: #"{"image":"couples/p1/a.png"}"#)
    _ = try await Self.client(up).uploadImage(Data([1, 2, 3]))
    let request = try #require(up.requests.first)
    #expect(request.headers["Content-Type"] == "image/png")
    #expect(request.body == Data([1, 2, 3]))

    let down = Server(body: "bytes")
    let bytes = try await Self.client(down).downloadImage(MediaKey("couples/p1/a.png"))
    #expect(bytes == Data("bytes".utf8))
    #expect(down.requests.first?.path == "/v1/media/couples/p1/a.png")
  }

  @Test func contractErrorsKeepTheirName() async {
    let server = Server(status: 409, body: #"{"_tag":"AlreadyPaired"}"#)
    await #expect(throws: TransportError.api(.alreadyPaired)) {
      try await Self.client(server).claimInvite(ClaimInviteRequest(code: InviteCode("ABC")))
    }
  }
}
