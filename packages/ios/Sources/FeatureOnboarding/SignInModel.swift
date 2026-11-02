import BilletKit
import Observation
import Persistence
import Transport

/// Runs ``SignInMachine`` against the backend and the device's account store.
@MainActor
@Observable
public final class SignInModel {
  private let store: Store<SignInMachine>

  public var state: SignInMachine.State { store.state }

  public init(api: APIClient, accounts: AccountStore) {
    store = Store<SignInMachine>(initial: .idle) { output in
      await SignInMachine.run(output, api: api, accounts: accounts)
    }
  }

  public func appeared() { store.send(.appeared) }
  public func retry() { store.send(.retried) }
  public func appleCompleted(identityToken: String) {
    store.send(.appleCompleted(identityToken: identityToken))
  }
  public func appleCancelled() { store.send(.appleCancelled) }
  public func appleFailed() { store.send(.appleFailed) }
  public func settled() async { await store.settled() }
}
