import BilletKit
import Observation
import Persistence
import Transport
import Wire

/// From launch to a saved session with no question asked: read the account key from the iCloud
/// Keychain (making it the first time), trade it for a session and save the session.
///
/// The same key on a new phone returns to the same account, so there is nothing to choose. The
/// only way to stop here is the network: `failed` waits for a retry. `request` counts the backend
/// calls so a late answer changes nothing.
public enum AnonymousSignInMachine: Machine {
  public enum State: Equatable, Sendable {
    case idle
    case signingIn(request: Int)
    case signedIn
    case failed(SignInFailure, request: Int)

    var request: Int {
      switch self {
      case .idle, .signedIn: 0
      case .signingIn(let request), .failed(_, let request): request
      }
    }
  }

  public enum Event: Equatable, Sendable {
    case appeared
    case retried
    case sessionSaved(request: Int)
    case failed(SignInFailure, request: Int)
  }

  public enum Output: Equatable, Sendable {
    case signIn(request: Int)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.idle, .appeared), (.failed, .retried):
      let request = state.request + 1
      return (.signingIn(request: request), [.signIn(request: request)])

    case (.signingIn(let current), .sessionSaved(let request)) where request == current:
      return (.signedIn, [])

    case (.signingIn(let current), .failed(let failure, let request)) where request == current:
      return (.failed(failure, request: current), [])

    case (.idle, _), (.signedIn, _), (.signingIn, _), (.failed, _):
      return (state, [])
    }
  }
}

extension AnonymousSignInMachine {
  public static func run(
    _ output: Output, api: APIClient, keys: AccountKeyStore, accounts: AccountStore
  ) async -> Event? {
    switch output {
    case .signIn(let request):
      let key: String
      do {
        key = try keys.loadOrCreate()
      } catch {
        return .failed(.storage, request: request)
      }
      let session: SessionResponse
      do {
        session = try await api.signInAnonymously(
          SignInAnonymouslyRequest(accountKey: AccountKey(key)))
      } catch {
        return .failed(SignInFailure(error), request: request)
      }
      // Each launch signs in again; the same account keeps the pair this phone saved for it.
      let saved = (try? accounts.load())?.record
      let samePair = saved?.userID == session.userId.rawValue ? saved : nil
      do {
        try accounts.save(
          session.sessionToken.rawValue,
          AccountRecord(
            userID: session.userId.rawValue, deviceID: session.deviceId.rawValue,
            expiresAt: session.expiresAt, isPaired: samePair?.isPaired ?? false,
            pairID: samePair?.pairID))
        return .sessionSaved(request: request)
      } catch {
        return .failed(.storage, request: request)
      }
    }
  }
}

/// Runs ``AnonymousSignInMachine`` against the backend, the iCloud Keychain and the account store.
@MainActor
@Observable
public final class AnonymousSignInModel {
  private let store: Store<AnonymousSignInMachine>

  public var state: AnonymousSignInMachine.State { store.state }

  public init(api: APIClient, keys: AccountKeyStore, accounts: AccountStore) {
    store = Store<AnonymousSignInMachine>(initial: .idle) { output in
      await AnonymousSignInMachine.run(output, api: api, keys: keys, accounts: accounts)
    }
  }

  public func appeared() { store.send(.appeared) }
  public func retry() { store.send(.retried) }
  public func settled() async { await store.settled() }
}
