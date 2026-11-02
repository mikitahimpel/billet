import AuthenticationServices
import Foundation
import Persistence
import Testing
import Transport
import Wire

@testable import FeatureOnboarding

@Suite struct SignInMachineTests {
  typealias M = SignInMachine

  @Test func theHappyPathEndsSignedIn() {
    var (state, outputs) = M.transition(.idle, .appeared)
    #expect(state == .fetchingNonce(request: 1))
    #expect(outputs == [.fetchNonce(request: 1)])

    (state, _) = M.transition(state, .nonceFetched("n", request: 1))
    #expect(state == .ready(nonce: "n", request: 1))

    (state, outputs) = M.transition(state, .appleCompleted(identityToken: "jwt"))
    #expect(state == .exchanging(request: 2))
    #expect(outputs == [.exchange(identityToken: "jwt", request: 2)])

    (state, _) = M.transition(state, .sessionSaved(request: 2))
    #expect(state == .signedIn)
  }

  @Test func closingAppleSheetKeepsTheButton() {
    let ready = M.State.ready(nonce: "n", request: 1)
    #expect(M.transition(ready, .appleCancelled).0 == ready)
  }

  @Test func appleFailingShowsAFailureThatRetryRecovers() {
    var (state, _) = M.transition(.ready(nonce: "n", request: 1), .appleFailed)
    #expect(state == .failed(.appleRefused, request: 1))
    let outputs: [M.Output]
    (state, outputs) = M.transition(state, .retried)
    #expect(state == .fetchingNonce(request: 2))
    #expect(outputs == [.fetchNonce(request: 2)])
  }

  @Test func aLateAnswerIsDropped() {
    let state = M.State.fetchingNonce(request: 3)
    #expect(M.transition(state, .nonceFetched("n", request: 2)).0 == state)
    #expect(M.transition(state, .failed(.unavailable, request: 2)).0 == state)
  }

  @Test func theExchangeOnlyFollowsAnIdentityTokenFromReady() {
    for state in [M.State.idle, .fetchingNonce(request: 1), .exchanging(request: 1), .signedIn] {
      #expect(M.transition(state, .appleCompleted(identityToken: "x")).1.isEmpty)
    }
  }

  @Test(arguments: [
    (TransportError.api(.unauthorized), SignInFailure.rejected),
    (.api(.unavailable), .unavailable),
    (.network("x"), .unavailable),
    (.decoding, .unavailable),
  ])
  func failuresMapToWhatTheUserCanDo(error: TransportError, failure: SignInFailure) {
    #expect(SignInFailure(error) == failure)
  }

  @Test func eachFailureHasItsOwnWords() {
    let all: [SignInFailure] = [.appleRefused, .rejected, .unavailable, .storage]
    #expect(Set(all.map(\.message)).count == all.count)
  }
}

@Suite @MainActor struct SignInModelTests {
  nonisolated static let session = SessionResponse(
    sessionToken: SessionToken("tok"), expiresAt: 99, userId: UserId("u1"),
    deviceId: DeviceId("d1"))

  static func api(sign: @escaping @Sendable () throws(TransportError) -> SessionResponse)
    -> APIClient
  {
    var api = APIClient.offline
    api.authChallenge = { () async throws(TransportError) in
      AuthChallengeResponse(nonce: AuthNonce(String(repeating: "a", count: 43)), expiresAt: 1)
    }
    api.signInWithApple = { (_) async throws(TransportError) in try sign() }
    return api
  }

  final class Memory: @unchecked Sendable {
    private let lock = NSLock()
    private var saved: (String, AccountRecord)?
    var failSaving = false

    var value: (String, AccountRecord)? { lock.withLock { saved } }

    var store: AccountStore {
      AccountStore(
        load: { [self] () throws(PersistenceError) in
          lock.withLock { saved.map { (token: $0.0, record: $0.1) } }
        },
        save: { [self] (token, record) throws(PersistenceError) in
          if failSaving { throw .storage("full") }
          lock.withLock { saved = (token, record) }
        },
        setPaired: { (_, _) throws(PersistenceError) in },
        clear: { () throws(PersistenceError) in })
    }
  }

  @Test func aNewInstallReachesSignedInAndSavesTheSession() async {
    let memory = Memory()
    let model = SignInModel(api: Self.api(sign: { Self.session }), accounts: memory.store)
    model.appeared()
    await model.settled()
    #expect(model.state == .ready(nonce: String(repeating: "a", count: 43), request: 1))
    model.appleCompleted(identityToken: "jwt")
    await model.settled()
    #expect(model.state == .signedIn)
    #expect(memory.value?.0 == "tok")
    #expect(memory.value?.1 == AccountRecord(userID: "u1", deviceID: "d1", expiresAt: 99))
  }

  @Test func theBackendRefusingTheTokenShowsRejected() async {
    let memory = Memory()
    let model = SignInModel(
      api: Self.api(sign: { () throws(TransportError) in throw .api(.unauthorized) }),
      accounts: memory.store)
    model.appeared()
    await model.settled()
    model.appleCompleted(identityToken: "jwt")
    await model.settled()
    #expect(model.state == .failed(.rejected, request: 2))
    #expect(memory.value == nil)
  }

  @Test func aSessionThatCannotBeSavedIsNotSignedIn() async {
    let memory = Memory()
    memory.failSaving = true
    let model = SignInModel(api: Self.api(sign: { Self.session }), accounts: memory.store)
    model.appeared()
    await model.settled()
    model.appleCompleted(identityToken: "jwt")
    await model.settled()
    #expect(model.state == .failed(.storage, request: 2))
  }

  @Test func theNonceIsFetchedAgainOnRetry() async {
    let calls = Counter()
    var api = Self.api(sign: { Self.session })
    api.authChallenge = { () async throws(TransportError) in
      if calls.next() == 0 { throw .network("offline") }
      return AuthChallengeResponse(
        nonce: AuthNonce(String(repeating: "b", count: 43)), expiresAt: 1)
    }
    let model = SignInModel(api: api, accounts: Memory().store)
    model.appeared()
    await model.settled()
    #expect(model.state == .failed(.unavailable, request: 1))
    model.retry()
    await model.settled()
    #expect(model.state == .ready(nonce: String(repeating: "b", count: 43), request: 2))
  }

  @Test func appleSheetResultsMapToEvents() {
    #expect(
      OnboardingView.outcome(of: .failure(ASAuthorizationError(.canceled))) == .cancelled)
    #expect(OnboardingView.outcome(of: .failure(ASAuthorizationError(.failed))) == .failed)
    #expect(
      OnboardingView.outcome(of: .failure(URLError(.notConnectedToInternet))) == .failed)
  }
}

final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  func next() -> Int {
    lock.withLock {
      count += 1
      return count - 1
    }
  }
}
