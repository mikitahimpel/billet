import Foundation
import Persistence
import Testing
import Transport
import WidgetBridge
import Wire

@testable import FeatureHome

/// The statuses these tests hear.
private enum Status {
  static let down = AppStatus(
    maintenance: MaintenanceStatus(
      active: true, message: StatusMessage(key: "maintenance.default", text: "Resting.")))
  static let notice = StatusMessage(key: "notice.slow", text: "Slow tonight.")
}

@Suite @MainActor struct ServiceStatusModelTests {
  /// The service's status as the fake server has it now, and a count of the times it was asked.
  final class Service: @unchecked Sendable {
    private let lock = NSLock()
    private var answer: Result<AppStatus, TransportError> = .success(.normal)
    private var asked = 0

    var checks: Int { lock.withLock { asked } }
    func set(_ answer: Result<AppStatus, TransportError>) { lock.withLock { self.answer = answer } }

    var fetch: ServiceStatusModel.Fetch {
      { [self] () async throws(TransportError) -> AppStatus in
        try lock.withLock { () -> Result<AppStatus, TransportError> in
          asked += 1
          return answer
        }.get()
      }
    }
  }

  private func defaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "ServiceStatusModelTests.\(UUID().uuidString)"))
  }

  @Test func aCheckTakesTheServicesStatus() async {
    let service = Service()
    service.set(.success(Status.down))
    let model = ServiceStatusModel(appVersion: "1.0+1", fetch: service.fetch)
    await model.check()
    #expect(model.screen == .maintenance(Status.down.maintenance))
  }

  @Test(arguments: [
    TransportError.network("offline"), .status(500), .decoding, .api(.unavailable),
  ])
  func aFailedCheckKeepsWhatWasHeard(_ error: TransportError) async {
    let service = Service()
    service.set(.success(Status.down))
    let model = ServiceStatusModel(appVersion: "1.0+1", fetch: service.fetch)
    await model.check()
    service.set(.failure(error))
    await model.check()
    #expect(model.screen == .maintenance(Status.down.maintenance))
  }

  @Test func aMaintenanceFailureIsTakenAsTheStatus() async {
    let service = Service()
    service.set(.failure(.maintenance(Status.down)))
    let model = ServiceStatusModel(appVersion: "1.0+1", fetch: service.fetch)
    await model.check()
    #expect(model.screen == .maintenance(Status.down.maintenance))
  }

  @Test func aBuildWithNowhereToAskStaysNormal() async {
    let model = ServiceStatusModel(appVersion: "1.0+1", fetch: nil)
    await model.check()
    #expect(model.screen == .normal(notice: nil))
  }

  @Test func theAppsVersionDecidesAnUpdate() {
    let model = ServiceStatusModel(appVersion: "1.2.0+14", fetch: nil)
    model.received(
      AppStatus(maintenance: MaintenanceStatus(active: false), minVersion: AppVersion("1.2.0+15")))
    #expect(model.screen == .updateRequired)
  }

  @Test func runningChecksAgainEveryMinuteUntilCancelled() async {
    let service = Service()
    let naps = AsyncStream.makeStream(of: Duration.self)
    let model = ServiceStatusModel(
      appVersion: "1.0+1", fetch: service.fetch,
      sleep: { duration in
        naps.continuation.yield(duration)
        try? await Task.sleep(for: .milliseconds(1))
      })
    let running = Task { await model.run() }
    var waits: [Duration] = []
    for await nap in naps.stream {
      waits.append(nap)
      if waits.count == 3 { break }
    }
    running.cancel()
    await running.value
    #expect(waits == Array(repeating: ServiceStatusModel.checkEvery, count: 3))
    #expect(service.checks >= 3)
  }

  @Test func aDismissedNoticeStaysDismissedAfterTheNextLaunch() throws {
    let defaults = try defaults()
    let status = AppStatus(maintenance: MaintenanceStatus(active: false), notice: Status.notice)
    let first = ServiceStatusModel(appVersion: nil, fetch: nil, memory: .defaults(defaults))
    first.received(status)
    #expect(first.noticeText == "Slow tonight.")
    first.dismissNotice()
    #expect(first.noticeText == nil)

    let next = ServiceStatusModel(appVersion: nil, fetch: nil, memory: .defaults(defaults))
    next.received(status)
    #expect(next.screen == .normal(notice: nil))
  }

  @Test func theNoticeUsesTheAppsOwnString() {
    let model = ServiceStatusModel(
      appVersion: nil, fetch: nil, strings: { $0 == "notice.slow" ? "Ours." : nil })
    model.received(AppStatus(maintenance: MaintenanceStatus(active: false), notice: Status.notice))
    #expect(model.noticeText == "Ours.")
  }

  @Test func theEndOfMaintenanceIsCounted() {
    let model = ServiceStatusModel(appVersion: nil, fetch: nil)
    model.received(Status.down)
    model.received(Status.down)
    #expect(model.maintenanceEnds == 0)
    model.received(.normal)
    #expect(model.maintenanceEnds == 1)
  }

  @Test func theFlagsAnswerHandsOnItsStatus() async {
    var api = APIClient.offline
    api.flags = { () async throws(TransportError) in FlagsResponse(flags: [], status: Status.down) }
    let labs = WidgetFeaturesModel(store: nil)
    #expect(await FlagsRefresher(api: api, labs: labs).refresh() == Status.down)
  }

  // MARK: the real client

  /// Events and status as the real backend has them: writes refused while maintenance is on.
  final class Backend: @unchecked Sendable {
    private let lock = NSLock()
    private var down = true
    private var batches: [[ClientEvent]] = []

    var sent: [[ClientEvent]] { lock.withLock { batches } }
    func end() { lock.withLock { down = false } }

    var api: APIClient {
      var client = APIClient.offline
      client.flags = { [self] () async throws(TransportError) in
        FlagsResponse(flags: [], status: lock.withLock { down } ? Status.down : .normal)
      }
      client.reportEvents = { [self] (events) async throws(TransportError) in
        let status = lock.withLock { () -> AppStatus? in
          if down { return Status.down }
          batches.append(events)
          return nil
        }
        if let status { throw .maintenance(status) }
      }
      return client
    }
  }

  @Test func whatMaintenanceRefusedIsSentOnceItEnds() async {
    let backend = Backend()
    let status = ServiceStatusModel(appVersion: "1.0+1", fetch: nil)
    let model = RealAppModel(
      api: backend.api,
      accounts: AccountStore(
        load: { nil }, save: { _, _ in }, setPaired: { _, _ in }, clear: {}),
      keys: AccountKeyStore(
        loadOrCreate: { () throws(PersistenceError) in "k" },
        clear: { () throws(PersistenceError) in }),
      baseURL: URL(fileURLWithPath: "/"),
      labs: WidgetFeaturesModel(store: nil),
      eventStorage: .directory(
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
      widgetKinds: { [] },
      serviceStatus: status)

    await model.becameActive()
    #expect(status.screen == .maintenance(Status.down.maintenance))
    #expect(backend.sent.isEmpty)

    backend.end()
    status.received(.normal)
    #expect(status.maintenanceEnds == 1)
    await model.maintenanceEnded()
    #expect(backend.sent == [[ClientEvent(.appOpened)]])
  }
}
