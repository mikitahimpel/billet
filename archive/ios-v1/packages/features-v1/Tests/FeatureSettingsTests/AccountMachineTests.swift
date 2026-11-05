import Foundation
import Persistence
import Testing
import Transport
import Wire

@testable import FeatureSettings

@Suite struct AccountMachineTests {
  typealias M = AccountMachine

  @Test func anActionNeedsConfirmingBeforeItRuns() {
    var (state, outputs) = M.transition(.initial, .requested(.unpair))
    #expect(state == .confirming(.unpair, request: 0))
    #expect(outputs.isEmpty)
    (state, outputs) = M.transition(state, .confirmed)
    #expect(state == .working(.unpair, request: 1))
    #expect(outputs == [.perform(.unpair, request: 1)])
    (state, _) = M.transition(state, .succeeded(request: 1))
    #expect(state == .done(.unpair))
  }

  @Test func cancellingRunsNothing() {
    var (state, _) = M.transition(.initial, .requested(.signOut))
    let outputs: [M.Output]
    (state, outputs) = M.transition(state, .cancelled)
    #expect(state == .idle(request: 0))
    #expect(outputs.isEmpty)
  }

  @Test func confirmingFromNothingDoesNothing() {
    #expect(M.transition(.initial, .confirmed).1.isEmpty)
  }

  @Test func aFailedActionCanBeTriedAgainWithANewRequest() {
    var (state, _) = M.transition(.working(.unpair, request: 1), .failed(.unavailable, request: 1))
    #expect(state == .failed(.unpair, .unavailable, request: 1))
    (state, _) = M.transition(state, .confirmed)
    #expect(state == .working(.unpair, request: 2))
    // The first attempt answering late changes nothing.
    #expect(M.transition(state, .succeeded(request: 1)).0 == state)
  }

  @Test func aDoneActionStaysDone() {
    #expect(M.transition(.done(.signOut), .requested(.unpair)).0 == .done(.signOut))
  }
}

@Suite @MainActor struct AccountModelTests {
  final class Memory: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var record: AccountRecord? = AccountRecord(
      userID: "u", deviceID: "d", expiresAt: 1, isPaired: true, pairID: "p")
    private(set) var hasToken = true

    var store: AccountStore {
      AccountStore(
        load: { [self] () throws(PersistenceError) in
          lock.withLock { record.map { (token: "t", record: $0) } }
        },
        save: { (_, _) throws(PersistenceError) in },
        setPaired: { [self] (paired, id) throws(PersistenceError) in
          lock.withLock {
            record?.isPaired = paired
            record?.pairID = id
          }
        },
        clear: { [self] () throws(PersistenceError) in
          lock.withLock {
            record = nil
            hasToken = false
          }
        })
    }
  }

  /// The iCloud key, in memory.
  final class Keys: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var key: String? = "k"

    var store: AccountKeyStore {
      AccountKeyStore(
        loadOrCreate: { [self] () throws(PersistenceError) in lock.withLock { key ?? "new" } },
        clear: { [self] () throws(PersistenceError) in lock.withLock { key = nil } })
    }
  }

  static let health = DeliveryHealth(
    notifications: { .allowed }, widgets: { 2 }, backendReachable: { true })

  static func model(
    api: APIClient, memory: Memory, keys: Keys = Keys(),
    reauthorize: @escaping AppleReauthorizer = { .cancelled }
  ) -> AccountModel {
    AccountModel(
      api: api, accounts: memory.store, keys: keys.store, health: health,
      reauthorize: reauthorize)
  }

  @Test func unpairingCallsTheBackendAndKeepsTheAccount() async {
    let memory = Memory()
    let calls = Calls()
    var api = APIClient.offline
    api.unpair = { () async throws(TransportError) in calls.add("unpair") }
    let model = Self.model(api: api, memory: memory)
    model.request(.unpair)
    model.confirm()
    await model.settled()
    #expect(model.state == .done(.unpair))
    #expect(calls.names == ["unpair"])
    #expect(memory.record?.isPaired == false)
    #expect(memory.record?.pairID == nil)
    #expect(memory.hasToken)
  }

  @Test func anUnpairThatCannotReachTheBackendKeepsThePair() async {
    let memory = Memory()
    let model = Self.model(api: .offline, memory: memory)
    model.request(.unpair)
    model.confirm()
    await model.settled()
    #expect(model.state == .failed(.unpair, .unavailable, request: 1))
    #expect(memory.record?.isPaired == true)
  }

  @Test func signingOutForgetsTheAccountEvenOffline() async {
    let memory = Memory()
    let model = Self.model(api: .offline, memory: memory)
    model.request(.signOut)
    model.confirm()
    await model.settled()
    #expect(model.state == .done(.signOut))
    #expect(memory.record == nil)
    #expect(!memory.hasToken)
  }

  /// A backend that answers `account` with `linked`, and records each delete's body.
  static func deletingAPI(linked: Bool, sent: Sent) -> APIClient {
    var api = APIClient.offline
    api.account = { () async throws(TransportError) in
      AccountResponse(userId: UserId("u"), linked: linked)
    }
    api.deleteAccount = { (body) async throws(TransportError) in sent.add(body) }
    return api
  }

  final class Sent: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [DeleteAccountRequest] = []
    var bodies: [DeleteAccountRequest] { lock.withLock { list } }
    func add(_ body: DeleteAccountRequest) { lock.withLock { list.append(body) } }
  }

  @Test func deletingAnAnonymousAccountForgetsItOnEveryPhone() async {
    let memory = Memory()
    let keys = Keys()
    let sent = Sent()
    let model = Self.model(
      api: Self.deletingAPI(linked: false, sent: sent), memory: memory, keys: keys)
    model.request(.deleteAccount)
    #expect(model.state == .confirming(.deleteAccount, request: 0))
    model.confirm()
    await model.settled()
    #expect(model.state == .done(.deleteAccount))
    #expect(sent.bodies == [DeleteAccountRequest()])
    #expect(memory.record == nil)
    #expect(keys.key == nil)
  }

  @Test func deletingALinkedAccountSendsAFreshAppleCode() async {
    let sent = Sent()
    let model = Self.model(
      api: Self.deletingAPI(linked: true, sent: sent), memory: Memory(),
      reauthorize: { .code("apple-code") })
    model.request(.deleteAccount)
    model.confirm()
    await model.settled()
    #expect(model.state == .done(.deleteAccount))
    #expect(sent.bodies == [DeleteAccountRequest(appleAuthorizationCode: "apple-code")])
  }

  @Test func closingTheAppleSheetDeletesNothing() async {
    let memory = Memory()
    let keys = Keys()
    let sent = Sent()
    let model = Self.model(
      api: Self.deletingAPI(linked: true, sent: sent), memory: memory, keys: keys,
      reauthorize: { .cancelled })
    model.request(.deleteAccount)
    model.confirm()
    await model.settled()
    #expect(model.state == .failed(.deleteAccount, .appleCancelled, request: 1))
    #expect(sent.bodies.isEmpty)
    #expect(memory.record != nil)
    #expect(keys.key == "k")
  }

  @Test func aDeleteThatCannotReachTheBackendKeepsEverything() async {
    let memory = Memory()
    let keys = Keys()
    let model = Self.model(api: .offline, memory: memory, keys: keys)
    model.request(.deleteAccount)
    model.confirm()
    await model.settled()
    #expect(model.state == .failed(.deleteAccount, .unavailable, request: 1))
    #expect(memory.record != nil)
    #expect(keys.key == "k")
  }

  @Test func aRetryAfterTheServerDeletedOnlyForgets() async {
    let memory = Memory()
    let keys = Keys()
    var api = APIClient.offline
    api.account = { () async throws(TransportError) in throw .api(.unauthorized) }
    let model = Self.model(api: api, memory: memory, keys: keys)
    model.request(.deleteAccount)
    model.confirm()
    await model.settled()
    #expect(model.state == .done(.deleteAccount))
    #expect(memory.record == nil)
    #expect(keys.key == nil)
  }

  @Test func theHealthCheckReportsWhatItReads() async {
    let model = Self.model(api: .offline, memory: Memory())
    await model.checkHealth()
    #expect(
      model.report == HealthReport(notifications: .allowed, widgets: 2, backendReachable: true))
    #expect(model.report?.isHealthy == true)
  }
}

final class Calls: @unchecked Sendable {
  private let lock = NSLock()
  private var list: [String] = []
  var names: [String] { lock.withLock { list } }
  func add(_ name: String) { lock.withLock { list.append(name) } }
}

@Suite struct DeliveryHealthTests {
  @Test func notificationsOffIsAFailure() async {
    let health = DeliveryHealth(
      notifications: { .denied }, widgets: { 0 }, backendReachable: { true })
    let report = await health.check()
    #expect(!report.isHealthy)
    let line = report.lines.first { $0.title == "Notifications" }
    #expect(line?.ok == false)
    #expect(line?.detail.contains("iOS Settings") == true)
  }

  @Test func notAskedIsAlsoAFailure() async {
    let report = await DeliveryHealth(
      notifications: { .notAsked }, widgets: { 1 }, backendReachable: { true }
    ).check()
    #expect(!report.isHealthy)
  }

  @Test func noWidgetsIsNotAFailure() async {
    let report = await DeliveryHealth(
      notifications: { .allowed }, widgets: { 0 }, backendReachable: { true }
    ).check()
    #expect(report.isHealthy)
    #expect(
      report.lines.first { $0.title == "Widgets" }?.detail == "None on your Home or Lock Screen.")
  }

  @Test func anUnreachableBackendIsAFailure() async {
    let report = await DeliveryHealth(
      notifications: { .allowed }, widgets: { 1 }, backendReachable: { false }
    ).check()
    #expect(!report.isHealthy)
  }

  @Test func theBackendCountsAsReachableWhenItAnswersAtAll() async {
    var api = APIClient.offline
    api.listNotes = { (_) async throws(TransportError) in throw .api(.notFound) }
    #expect(await DeliveryHealth.reachability(of: api)() == true)
    #expect(await DeliveryHealth.reachability(of: .offline)() == false)
  }
}
