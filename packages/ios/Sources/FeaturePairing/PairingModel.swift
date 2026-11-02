import BilletKit
import Observation
import Transport

/// Runs ``PairingMachine`` against the backend.
@MainActor
@Observable
public final class PairingModel {
  private let store: Store<PairingMachine>

  public var state: PairingMachine.State { store.state }

  public init(api: APIClient) {
    store = Store<PairingMachine>(initial: .initial) { output in
      await PairingMachine.run(output, api: api)
    }
  }

  public func createInvite() { store.send(.createRequested) }
  public func submit(code: String) { store.send(.codeSubmitted(code)) }
  public func cancel() { store.send(.cancelled) }
  public func tick() { store.send(.ticked) }
  public func settled() async { await store.settled() }
}
