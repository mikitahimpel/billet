/// A StoreKit 2 transaction as Apple signed it (its JWS).
public struct PurchaseRequest: Codable, Hashable, Sendable {
  public let signedTransaction: String

  public init(signedTransaction: String) {
    self.signedTransaction = signedTransaction
  }
}

/// Dev server only: a fake purchase or refund from the mock store.
public struct MockPurchaseRequest: Codable, Hashable, Sendable {
  public enum Kind: String, Codable, Hashable, Sendable {
    case purchase
    case refund
  }

  public let productId: String
  public let transactionId: String
  public let kind: Kind

  public init(productId: String, transactionId: String, kind: Kind) {
    self.productId = productId
    self.transactionId = transactionId
    self.kind = kind
  }
}

/// `balance` is the pair's wallet after it, or a demo room's bought coins. `stamps` is the
/// contract's `coins`.
public struct PurchaseResponse: Codable, Hashable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case transactionId, productId, balance, duplicate
    case stamps = "coins"
  }

  public let transactionId: String
  public let productId: String
  public let stamps: Int
  public let balance: Int
  /// Already applied: the balance did not change.
  public let duplicate: Bool

  public init(
    transactionId: String, productId: String, stamps: Int, balance: Int, duplicate: Bool
  ) {
    self.transactionId = transactionId
    self.productId = productId
    self.stamps = stamps
    self.balance = balance
    self.duplicate = duplicate
  }
}

/// Sent by Apple, never by the app; here so every contract payload has a Swift twin.
public struct AppStoreNotificationRequest: Codable, Hashable, Sendable {
  public let signedPayload: String

  public init(signedPayload: String) {
    self.signedPayload = signedPayload
  }
}
