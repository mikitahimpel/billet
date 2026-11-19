import BilletKit
import Foundation
import Observation
import Payments
import WidgetBridge

/// The coin packs in the Coins sheet, sold through the build's store. The server credits a paid pack to the pair's
/// wallet, and the shop reads the new balance from there; nothing here counts coins.
@MainActor
@Observable
public final class CoinPacksModel {
  typealias Shelf = CoinShelfMachine.State
  typealias Status = CoinPurchaseMachine.State

  @ObservationIgnored private let payments: (any Payments)?
  private let shelfStore: Store<CoinShelfMachine>
  private let purchaseStore: Store<CoinPurchaseMachine>

  var shelf: Shelf { shelfStore.state }
  var status: Status { purchaseStore.state }

  public var packs: [StampPack] {
    switch shelf {
    case .ready(let packs): packs
    case .loading, .unavailable: []
    }
  }

  /// `credited` runs after the server took a pack or the ledger changed, to read the wallet again.
  public init(payments: (any Payments)?, credited: @escaping @MainActor @Sendable () async -> Void)
  {
    self.payments = payments
    shelfStore = Store(initial: payments == nil ? .unavailable : .loading) { output in
      switch output {
      case .loadProducts:
        guard let payments else { return .loadFailed }
        do throws(PaymentsError) {
          return .loaded(try await payments.products())
        } catch {
          return .loadFailed
        }
      }
    }
    purchaseStore = Store(initial: .idle) { output in
      switch output {
      case .purchase(let pack):
        guard let payments else { return .failed(.unavailable) }
        do throws(PaymentsError) {
          return switch try await payments.purchase(pack) {
          case .purchased(let credit): .purchased(coins: credit.stamps)
          case .cancelled: .cancelled
          case .pending: .pending
          case .awaitingCredit: .awaitingCredit
          }
        } catch {
          return .failed(error)
        }
      case .readWallet:
        await credited()
        return nil
      }
    }
  }

  /// The server's switch for selling coins (docs/payments.md).
  nonisolated static let flag = Experiment(key: "payments", variants: ["off", "on"])

  /// Packs on sale for this pair: only once the server turned `payments` on, whichever store the build carries, so a
  /// mock build that reaches testers or App Review sells nothing while the flag is off. Dev turns it on in the admin.
  nonisolated static func sells(_ flags: RemoteFlags) -> Bool {
    flags.variant(of: flag) == "on"
  }

  /// The smallest pack that covers `missing`, or the biggest when none does; nil when nothing is missing.
  nonisolated static func fit(for missing: Int, in packs: [StampPack]) -> StampPack? {
    guard missing > 0 else { return nil }
    let sorted = packs.sorted { $0.stamps < $1.stamps }
    return sorted.first { $0.stamps >= missing } ?? sorted.last
  }

  public func load() async {
    shelfStore.send(.opened)
    await shelfStore.settled()
  }

  /// A pack is on its way through the store; every buy waits for it.
  var isBuying: Bool {
    if case .buying = status { true } else { false }
  }

  public func buy(_ pack: StampPack) async {
    // A second pack tapped meanwhile is refused by the machine; only an accepted buy is waited for.
    guard !isBuying else { return purchaseStore.send(.buyTapped(pack)) }
    purchaseStore.send(.buyTapped(pack))
    await purchaseStore.settled()
  }

  /// Follows credits and refunds that arrive outside a purchase, for as long as the caller's task runs. A paid pack
  /// the server hadn't taken yet is sent again first.
  func follow() async {
    guard let payments else { return }
    let updates = payments.updates()
    if case .delivering = status { await payments.settleUnfinished() }
    for await update in updates {
      switch update {
      case .credited(let credit): purchaseStore.send(.credited(coins: credit.stamps))
      case .ledgerChanged: purchaseStore.send(.ledgerChanged)
      }
    }
    await purchaseStore.settled()
  }

  nonisolated static func message(_ error: PaymentsError) -> String {
    switch error {
    case .notAllowed: "Purchases are turned off on this iPhone."
    case .unavailable: "Couldn't reach the store. Nothing was charged; try again."
    case .rejected, .failed, .unknownProduct: "That didn't go through. Nothing was charged."
    }
  }
}
