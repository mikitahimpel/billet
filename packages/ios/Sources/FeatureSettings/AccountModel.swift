import BilletKit
import Observation
import Persistence
import Transport

/// Runs ``AccountMachine`` and the delivery health check for the Settings screen.
@MainActor
@Observable
public final class AccountModel {
  private let store: Store<AccountMachine>
  private let health: DeliveryHealth
  public private(set) var report: HealthReport?
  public private(set) var checking = false

  public var state: AccountMachine.State { store.state }

  public init(api: APIClient, accounts: AccountStore, health: DeliveryHealth) {
    self.health = health
    store = Store<AccountMachine>(initial: .initial) { output in
      await AccountMachine.run(output, api: api, accounts: accounts)
    }
  }

  public func request(_ action: AccountAction) { store.send(.requested(action)) }
  public func confirm() { store.send(.confirmed) }
  public func cancel() { store.send(.cancelled) }
  public func settled() async { await store.settled() }

  public func checkHealth() async {
    checking = true
    report = await health.check()
    checking = false
  }
}
