import BilletKit
import Payments

/// One coin pack on its way through the build's store. One buy at a time, so a store result always
/// belongs to the pack in `buying`.
public nonisolated enum CoinPurchaseMachine: Machine {
  public enum State: Equatable, Sendable {
    case idle
    case buying(String)
    /// The coins arrive once someone else approves, such as a parent's Ask to Buy.
    case waiting
    /// Paid, but the server hasn't credited it yet; the store sends it again until it has.
    case delivering
    case bought(coins: Int)
    case failed(PaymentsError)
  }

  public enum Event: Equatable, Sendable {
    case buyTapped(StampPack)
    case purchased(coins: Int)
    case cancelled
    case pending
    case awaitingCredit
    case failed(PaymentsError)
    /// A credit that came outside a purchase: Ask to Buy approved, or a transaction sent again.
    case credited(coins: Int)
    /// The server's ledger changed, such as after an App Store refund.
    case ledgerChanged
  }

  public enum Output: Equatable, Sendable {
    case purchase(StampPack)
    case readWallet
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.idle, .buyTapped(let pack)), (.waiting, .buyTapped(let pack)),
      (.delivering, .buyTapped(let pack)), (.bought, .buyTapped(let pack)),
      (.failed, .buyTapped(let pack)):
      (.buying(pack.id), [.purchase(pack)])
    case (.buying, .purchased(let coins)): (.bought(coins: coins), [.readWallet])
    case (.buying, .cancelled): (.idle, [])
    case (.buying, .pending): (.waiting, [])
    case (.buying, .awaitingCredit): (.delivering, [])
    case (.buying, .failed(let error)): (.failed(error), [])
    case (.waiting, .credited(let coins)), (.delivering, .credited(let coins)):
      (.bought(coins: coins), [.readWallet])
    // Coins that came some other way still move the balance; what this sheet says stays.
    case (.idle, .credited), (.buying, .credited), (.bought, .credited), (.failed, .credited),
      (.idle, .ledgerChanged), (.buying, .ledgerChanged), (.waiting, .ledgerChanged),
      (.delivering, .ledgerChanged), (.bought, .ledgerChanged), (.failed, .ledgerChanged):
      (state, [.readWallet])
    case (.buying, .buyTapped),
      (.idle, .purchased), (.waiting, .purchased), (.delivering, .purchased),
      (.bought, .purchased), (.failed, .purchased),
      (.idle, .cancelled), (.waiting, .cancelled), (.delivering, .cancelled),
      (.bought, .cancelled), (.failed, .cancelled),
      (.idle, .pending), (.waiting, .pending), (.delivering, .pending), (.bought, .pending),
      (.failed, .pending),
      (.idle, .awaitingCredit), (.waiting, .awaitingCredit), (.delivering, .awaitingCredit),
      (.bought, .awaitingCredit), (.failed, .awaitingCredit),
      (.idle, .failed), (.waiting, .failed), (.delivering, .failed), (.bought, .failed),
      (.failed, .failed):
      (state, [])
    }
  }
}
