/// The shop never talks to StoreKit directly. The implementation is picked at build time
/// (`BILLET_PAYMENTS`); either way the server credits the stamps through ``PaymentsServer``.
public protocol Payments: Sendable {
  /// In catalogue order, priced in the buyer's currency.
  func products() async throws(PaymentsError) -> [StampPack]

  /// Returns once the store has answered and, for a purchase, once the server has credited it.
  func purchase(_ pack: StampPack) async throws(PaymentsError) -> PurchaseResult

  /// Settles unfinished transactions and returns the server's ledger. Stamp packs are consumable,
  /// so nothing else is restored.
  func restore() async throws(PaymentsError) -> StampLedger

  /// Changes that arrive outside ``purchase(_:)``. Each subscriber gets its own stream.
  func updates() -> AsyncStream<PaymentsUpdate>
}

public struct StampPack: Hashable, Sendable, Identifiable {
  /// The App Store product ID.
  public let id: String
  public let stamps: Int
  public let displayName: String
  public let description: String
  /// Already in the buyer's currency.
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

public enum PurchaseResult: Hashable, Sendable {
  case purchased(StampCredit)
  case cancelled
  /// Such as Ask to Buy. The credit comes later through ``Payments/updates()``.
  case pending
}

public struct StampCredit: Hashable, Sendable {
  /// The same on every device of the pair: `purchase:<transaction>`.
  public let entryID: String
  public let transactionID: String
  public let productID: String
  public let stamps: Int
  /// After this credit.
  public let serverBalance: Int
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

public enum PaymentsUpdate: Hashable, Sendable {
  case credited(StampCredit)
  /// Such as after a refund: merge it.
  case ledgerChanged(StampLedger)
}

public enum PaymentsError: Error, Hashable, Sendable {
  /// Screen Time or a managed device.
  case notAllowed
  /// Safe to try again.
  case unavailable
  case failed(String)
  /// The server refused the transaction's signature, bundle or product.
  case rejected
  case unknownProduct(String)
}
