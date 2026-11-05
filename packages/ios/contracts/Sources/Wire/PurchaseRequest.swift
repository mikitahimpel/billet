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
/// pair's wallet balance after it (`GET /v1/coins`), or a demo room's bought coins. `stamps` is
/// the contract's `coins`.
public struct PurchaseResponse: Codable, Hashable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case transactionId, productId, balance, duplicate
    case stamps = "coins"
  }

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

/// `POST /v1/appstore/notifications`: an App Store Server Notification V2, as Apple sends it. The
/// app never sends this; it is here so the contract's every payload has a Swift twin.
public struct AppStoreNotificationRequest: Codable, Hashable, Sendable {
  public let signedPayload: String

  public init(signedPayload: String) {
    self.signedPayload = signedPayload
  }
}
