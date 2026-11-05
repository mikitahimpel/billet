import Foundation
import Testing
import Wire

@testable import Transport

/// The 503 every write meets during maintenance, told apart from every other failure.
@Suite struct MaintenanceTests {
  static let body = #"""
    {"error":"maintenance","status":{"maintenance":{"active":true,"until":"2026-11-03T22:30:00Z"}}}
    """#

  static let status = AppStatus(
    maintenance: MaintenanceStatus(active: true, until: "2026-11-03T22:30:00Z"))

  static func service(status: Int, body: String) -> HTTPService {
    HTTPService { _ in HTTPResponse(status: status, body: Data(body.utf8)) }
  }

  static let write = HTTPRequest(method: .post, path: "/v1/notes")

  /// Keeps each status it is told.
  final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [AppStatus] = []
    var all: [AppStatus] { lock.withLock { seen } }
    func add(_ status: AppStatus) { lock.withLock { seen.append(status) } }
  }

  @Test func theMaintenance503CarriesItsStatus() async {
    await #expect(throws: TransportError.maintenance(Self.status)) {
      try await Self.service(status: 503, body: Self.body).performEmpty(Self.write)
    }
  }

  @Test func anyOther503IsAPlainStatus() async {
    await #expect(throws: TransportError.status(503)) {
      try await Self.service(status: 503, body: "Service Unavailable").performEmpty(Self.write)
    }
    await #expect(throws: TransportError.status(503)) {
      try await Self.service(status: 503, body: #"{"error":"busy"}"#).performEmpty(Self.write)
    }
  }

  @Test func theMaintenanceBodyOnAnotherStatusIsNotMaintenance() async {
    await #expect(throws: TransportError.status(500)) {
      try await Self.service(status: 500, body: Self.body).performEmpty(Self.write)
    }
  }

  @Test func reportingTellsTheStatusAndStillFails() async {
    let reports = Reports()
    let http = Self.service(status: 503, body: Self.body)
      .reportingMaintenance { reports.add($0) }
    await #expect(throws: TransportError.maintenance(Self.status)) {
      try await http.performEmpty(Self.write)
    }
    #expect(reports.all == [Self.status])
  }

  @Test func reportingStaysQuietForEverythingElse() async throws {
    let reports = Reports()
    let ok = Self.service(status: 200, body: #"{"pairId":"p1"}"#)
      .reportingMaintenance { reports.add($0) }
    _ = try await ok.perform(Self.write, as: ClaimInviteResponse.self)
    let down = Self.service(status: 503, body: "down").reportingMaintenance { reports.add($0) }
    await #expect(throws: TransportError.status(503)) { try await down.performEmpty(Self.write) }
    #expect(reports.all.isEmpty)
  }

  @Test func theStatusRouteIsAskedWithoutAToken() async throws {
    let server = APIClientTests.Server(body: #"{"status":{"maintenance":{"active":false}}}"#)
    let response = try await APIClient.live(http: server.http, token: { "tok" }).status()
    #expect(response.status == .normal)
    let request = try #require(server.requests.first)
    #expect(request.method == .get)
    #expect(request.path == "/v1/status")
    #expect(request.headers["Authorization"] == nil)
  }
}
