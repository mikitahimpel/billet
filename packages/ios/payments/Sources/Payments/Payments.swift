/// Buying stamps with money. The shop and the app talk to this protocol only, never to StoreKit:
/// every value crossing it is a plain type from this module.
///
/// Which implementation a build carries is chosen when it is built (`BILLET_PAYMENTS`, see
/// docs/payments.md): `PaymentsMock` fakes the store, `PaymentsStoreKit` is Apple's. Either way the
/// stamps are credited by the server, through ``PaymentsServer``, and the app's own ledger follows
/// what the server answered.
public protocol Payments: Sendable {
  /// The packs on sale, with their prices in the buyer's currency, in catalogue order.
  func products() async throws(PaymentsError) -> [StampPack]

  /// Buys one pack. Returns once the store has answered and, for a purchase, once the server has
  /// credited it.
  func purchase(_ pack: StampPack) async throws(PaymentsError) -> PurchaseResult

  /// Settles anything the store still holds unfinished and returns the server's ledger, which the
  /// app merges into its own. Stamp packs are consumable, so nothing else is restored.
  func restore() async throws(PaymentsError) -> StampLedger

  /// Changes that arrive outside ``purchase(_:)``: an approved Ask to Buy, a purchase finished on
  /// another launch, a refund. Each subscriber gets its own stream.
  func updates() -> AsyncStream<PaymentsUpdate>
}

/// One stamp pack as the store sells it.
public struct StampPack: Hashable, Sendable, Identifiable {
  /// The App Store product ID, such as `com.mikitahimpel.billet.coins.100`.
  public let id: String
  public let stamps: Int
  public let displayName: String
  public let description: String
  /// The price as the store shows it, already in the buyer's currency.
  public let displayPrice: String

  public init(
    id: String, stamps: Int, displayName: String, description: String, displayPrice: String
  ) {
    self.id = id
    self.stamps = stamps
    self.displayName = displayName
    self.description = description
    self.displayPrice = displayPrice
  }
}

/// How a purchase ended.
public enum PurchaseResult: Hashable, Sendable {
  /// Paid and credited by the server.
  case purchased(StampCredit)
  /// The buyer closed the sheet. Nothing was charged.
  case cancelled
  /// Waiting on someone else, such as a parent's Ask to Buy. The credit comes later through
  /// ``Payments/updates()``.
  case pending
}

/// Stamps the server credited for one transaction.
public struct StampCredit: Hashable, Sendable {
  /// The ledger entry ID, the same on every device of the pair: `purchase:<transaction>`.
  public let entryID: String
  public let transactionID: String
  public let productID: String
  public let stamps: Int
  /// The pair's bought stamps on the server after this credit.
  public let serverBalance: Int
  /// True when the server had already credited this transaction.
  public let duplicate: Bool

  public init(
    entryID: String, transactionID: String, productID: String, stamps: Int, serverBalance: Int,
    duplicate: Bool
  ) {
    self.entryID = entryID
    self.transactionID = transactionID
    self.productID = productID
    self.stamps = stamps
    self.serverBalance = serverBalance
    self.duplicate = duplicate
  }
}

/// What happened outside a purchase call.
public enum PaymentsUpdate: Hashable, Sendable {
  case credited(StampCredit)
  /// The server's ledger changed, such as after a refund: merge it.
  case ledgerChanged(StampLedger)
}

public enum PaymentsError: Error, Hashable, Sendable {
  /// Purchases are off on this device (Screen Time, a managed device).
  case notAllowed
  /// The store or the server could not be reached. Safe to try again.
  case unavailable
  /// The store said no, or answered something unexpected.
  case failed(String)
  /// The server would not credit the transaction (its signature, bundle or product).
  case rejected
  case unknownProduct(String)
}
