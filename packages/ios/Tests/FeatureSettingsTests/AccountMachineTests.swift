import Foundation
import Persistence
import Testing
import Transport

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

  static let health = DeliveryHealth(
    notifications: { .allowed }, widgets: { 2 }, backendReachable: { true })

  @Test func unpairingCallsTheBackendAndKeepsTheAccount() async {
    let memory = Memory()
    let calls = Calls()
    var api = APIClient.offline
    api.unpair = { () async throws(TransportError) in calls.add("unpair") }
    let model = AccountModel(api: api, accounts: memory.store, health: Self.health)
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
    let model = AccountModel(api: .offline, accounts: memory.store, health: Self.health)
    model.request(.unpair)
    model.confirm()
    await model.settled()
    #expect(model.state == .failed(.unpair, .unavailable, request: 1))
    #expect(memory.record?.isPaired == true)
  }

  @Test func signingOutForgetsTheAccountEvenOffline() async {
    let memory = Memory()
    let model = AccountModel(api: .offline, accounts: memory.store, health: Self.health)
    model.request(.signOut)
    model.confirm()
    await model.settled()
    #expect(model.state == .done(.signOut))
    #expect(memory.record == nil)
    #expect(!memory.hasToken)
  }

  @Test func theHealthCheckReportsWhatItReads() async {
    let model = AccountModel(api: .offline, accounts: Memory().store, health: Self.health)
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
