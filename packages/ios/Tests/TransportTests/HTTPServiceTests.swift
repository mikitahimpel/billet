import Foundation
import Testing
import Wire

@testable import Transport

@Suite struct HTTPServiceTests {
  static func service(status: Int, body: String) -> HTTPService {
    HTTPService { _ in HTTPResponse(status: status, body: Data(body.utf8)) }
  }

  static let request = HTTPRequest(method: .get, path: "x")

  @Test func decodesASuccessfulBody() async throws {
    let service = Self.service(status: 200, body: #"{"pairId":"p1"}"#)
    let response = try await service.perform(Self.request, as: ClaimInviteResponse.self)
    #expect(response == ClaimInviteResponse(pairId: PairId("p1")))
  }

  @Test func contractErrorsBecomeApiErrors() async {
    let service = Self.service(status: 401, body: #"{"_tag":"Unauthorized"}"#)
    await #expect(throws: TransportError.api(.unauthorized)) {
      try await service.perform(Self.request, as: ClaimInviteResponse.self)
    }
  }

  @Test func otherFailuresKeepTheStatus() async {
    let service = Self.service(status: 502, body: "bad gateway")
    await #expect(throws: TransportError.status(502)) {
      try await service.perform(Self.request, as: ClaimInviteResponse.self)
    }
  }

  @Test func malformedSuccessIsADecodingError() async {
    let service = Self.service(status: 200, body: #"{"pairId":""}"#)
    await #expect(throws: TransportError.decoding) {
      try await service.perform(Self.request, as: ClaimInviteResponse.self)
    }
  }

  @Test func sendFailuresPropagate() async {
    let service = HTTPService { _ throws(TransportError) in throw .network("offline") }
    await #expect(throws: TransportError.network("offline")) {
      try await service.perform(Self.request, as: ClaimInviteResponse.self)
    }
  }

  @Test func jsonRequestsEncodeTheBody() throws {
    let request = try HTTPRequest.json(
      .post, path: "x", body: ClaimInviteRequest(code: InviteCode("abc")))
    #expect(request.method == .post)
    #expect(request.headers["Content-Type"] == "application/json")
    #expect(request.body.map { String(decoding: $0, as: UTF8.self) } == #"{"code":"abc"}"#)
  }
}
