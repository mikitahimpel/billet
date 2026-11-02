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

  @Test(arguments: ["https://evil.example/x", "//evil.example/x", "ftp://evil.example"])
  func aPathCannotReplaceTheBaseHost(_ path: String) async throws {
    RecordingProtocol.hosts.withLock { $0 = [] }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingProtocol.self]
    let service = HTTPService.urlSession(
      baseURL: try #require(URL(string: "https://api.example")),
      session: URLSession(configuration: configuration))

    let request = HTTPRequest(
      method: .get, path: path, headers: ["Authorization": "secret"], body: nil)
    await #expect(throws: TransportError.network("invalid path \(path)")) {
      try await service.perform(request, as: ClaimInviteResponse.self)
    }
    #expect(RecordingProtocol.hosts.withLock { $0 }.isEmpty)
  }

  @Test func aPlainPathGoesToTheBaseHost() async throws {
    RecordingProtocol.hosts.withLock { $0 = [] }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingProtocol.self]
    let service = HTTPService.urlSession(
      baseURL: try #require(URL(string: "https://api.example")),
      session: URLSession(configuration: configuration))

    _ = try? await service.perform(
      HTTPRequest(method: .get, path: "v1/x", headers: [:], body: nil), as: ClaimInviteResponse.self
    )
    #expect(RecordingProtocol.hosts.withLock { $0 } == ["api.example"])
  }
}

/// Records the host of each request it is asked to load, and answers with an empty 200.
final class RecordingProtocol: URLProtocol, @unchecked Sendable {
  static let hosts = LockedValue<[String]>([])

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.hosts.withLock { $0.append(request.url?.host ?? "") }
    let response = HTTPURLResponse(
      url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200, httpVersion: nil,
      headerFields: nil)
    if let response {
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
    client?.urlProtocol(self, didLoad: Data("{}".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

final class LockedValue<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) { self.value = value }

  func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
    lock.lock()
    defer { lock.unlock() }
    return body(&value)
  }
}
