/// `POST /v1/purchases`: a StoreKit 2 transaction as Apple signed it (its JWS).
public struct PurchaseRequest: Codable, Hashable, Sendable {
  public let signedTransaction: String

  public init(signedTransaction: String) {
    self.signedTransaction = signedTransaction
  }
}

/// `POST /v1/purchases/mock`, on the dev server only: a fake purchase or refund from the mock
/// store.
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

/// What the server credited (or, for a mock refund, took back) for one transaction, and the
/// pair's bought stamps after it.
public struct PurchaseResponse: Codable, Hashable, Sendable {
  public let transactionId: String
  public let productId: String
  public let stamps: Int
  public let balance: Int
  /// True when this transaction had already been applied: the balance did not change.
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
