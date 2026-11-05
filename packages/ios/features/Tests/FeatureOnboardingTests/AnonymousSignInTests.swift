import Foundation
import Persistence
import Testing
import Transport
import Wire

@testable import FeatureOnboarding

@Suite struct AnonymousSignInMachineTests {
  typealias M = AnonymousSignInMachine

  @Test func signsInOnFirstAppearanceWithNoQuestion() {
    var (state, outputs) = M.transition(.idle, .appeared)
    #expect(state == .signingIn(request: 1))
    #expect(outputs == [.signIn(request: 1)])
    (state, outputs) = M.transition(state, .sessionSaved(request: 1))
    #expect(state == .signedIn)
    #expect(outputs.isEmpty)
  }

  @Test func aFailureWaitsForARetry() {
    var (state, _) = M.transition(.signingIn(request: 1), .failed(.unavailable, request: 1))
    #expect(state == .failed(.unavailable, request: 1))
    let outputs: [M.Output]
    (state, outputs) = M.transition(state, .retried)
    #expect(state == .signingIn(request: 2))
    #expect(outputs == [.signIn(request: 2)])
  }

  @Test func aLateAnswerIsDropped() {
    let state = M.State.signingIn(request: 2)
    #expect(M.transition(state, .sessionSaved(request: 1)).0 == state)
    #expect(M.transition(state, .failed(.unavailable, request: 1)).0 == state)
  }

  @Test func appearingAgainStartsNothingNew() {
    for state in [M.State.signingIn(request: 1), .signedIn, .failed(.storage, request: 1)] {
      #expect(M.transition(state, .appeared).1.isEmpty)
    }
  }
}

@Suite @MainActor struct AnonymousSignInModelTests {
  nonisolated static let session = SessionResponse(
    sessionToken: SessionToken("tok"), expiresAt: 99, userId: UserId("u1"),
    deviceId: DeviceId("d1"))

  final class Sent: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String] = []
    var all: [String] { lock.withLock { keys } }
    func add(_ key: String) { lock.withLock { keys.append(key) } }
  }

  static func keys(_ value: String? = String(repeating: "k", count: 43)) -> AccountKeyStore {
    AccountKeyStore(
      loadOrCreate: { () throws(PersistenceError) -> String in
        guard let value else { throw .keychain(status: -34018) }
        return value
      },
      clear: { () throws(PersistenceError) in })
  }

  @Test func tradesTheKeyForASessionAndSavesIt() async {
    let memory = SignInModelTests.Memory()
    let sent = Sent()
    var api = APIClient.offline
    api.signInAnonymously = { (body) async throws(TransportError) in
      sent.add(body.accountKey.rawValue)
      return Self.session
    }
    let model = AnonymousSignInModel(api: api, keys: Self.keys(), accounts: memory.store)
    model.appeared()
    await model.settled()
    #expect(model.state == .signedIn)
    #expect(sent.all == [String(repeating: "k", count: 43)])
    #expect(memory.value?.0 == "tok")
    #expect(memory.value?.1 == AccountRecord(userID: "u1", deviceID: "d1", expiresAt: 99))
  }

  @Test func signingInAgainKeepsThePairOfTheSameAccount() async {
    let paired = AccountRecord(
      userID: "u1", deviceID: "d0", expiresAt: 1, isPaired: true, pairID: "p1")
    let memory = SignInModelTests.Memory(saved: ("old", paired))
    var api = APIClient.offline
    api.signInAnonymously = { (_) async throws(TransportError) in Self.session }
    let model = AnonymousSignInModel(api: api, keys: Self.keys(), accounts: memory.store)
    model.appeared()
    await model.settled()
    #expect(
      memory.value?.1
        == AccountRecord(userID: "u1", deviceID: "d1", expiresAt: 99, isPaired: true, pairID: "p1"))
  }

  @Test func anotherAccountStartsUnpaired() async {
    let paired = AccountRecord(
      userID: "u0", deviceID: "d0", expiresAt: 1, isPaired: true, pairID: "p1")
    let memory = SignInModelTests.Memory(saved: ("old", paired))
    var api = APIClient.offline
    api.signInAnonymously = { (_) async throws(TransportError) in Self.session }
    let model = AnonymousSignInModel(api: api, keys: Self.keys(), accounts: memory.store)
    model.appeared()
    await model.settled()
    #expect(memory.value?.1 == AccountRecord(userID: "u1", deviceID: "d1", expiresAt: 99))
  }

  @Test func offlineWaitsAndRetriesWithTheSameKey() async {
    let sent = Sent()
    var api = APIClient.offline
    api.signInAnonymously = { (body) async throws(TransportError) in
      sent.add(body.accountKey.rawValue)
      if sent.all.count == 1 { throw .network("offline") }
      return Self.session
    }
    let model = AnonymousSignInModel(
      api: api, keys: Self.keys(), accounts: SignInModelTests.Memory().store)
    model.appeared()
    await model.settled()
    #expect(model.state == .failed(.unavailable, request: 1))
    model.retry()
    await model.settled()
    #expect(model.state == .signedIn)
    #expect(Set(sent.all).count == 1)
  }

  @Test func aKeychainThatCannotHoldTheKeyAsksNothingOfTheServer() async {
    let sent = Sent()
    var api = APIClient.offline
    api.signInAnonymously = { (body) async throws(TransportError) in
      sent.add(body.accountKey.rawValue)
      return Self.session
    }
    let model = AnonymousSignInModel(
      api: api, keys: Self.keys(nil), accounts: SignInModelTests.Memory().store)
    model.appeared()
    await model.settled()
    #expect(model.state == .failed(.storage, request: 1))
    #expect(sent.all.isEmpty)
  }
}
