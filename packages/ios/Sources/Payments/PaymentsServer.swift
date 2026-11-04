/// The server half of a purchase, as closures over plain values so this module needs no
/// networking. The app builds it from its API client; tests pass fakes.
public struct PaymentsServer: Sendable {
  /// What the server answered for one transaction.
  public struct Answer: Hashable, Sendable {
    public let transactionID: String
    public let productID: String
    public let stamps: Int
    public let balance: Int
    public let duplicate: Bool

    public init(
      transactionID: String, productID: String, stamps: Int, balance: Int, duplicate: Bool
    ) {
      self.transactionID = transactionID
      self.productID = productID
      self.stamps = stamps
      self.balance = balance
      self.duplicate = duplicate
    }

    /// The credit this answer stands for, under the entry ID the server's ledger uses.
    public var credit: StampCredit {
      StampCredit(
        entryID: "purchase:\(transactionID)", transactionID: transactionID, productID: productID,
        stamps: stamps, serverBalance: balance, duplicate: duplicate)
    }
  }

  public enum MockKind: String, Hashable, Sendable {
    case purchase
    case refund
  }

  /// Sends a StoreKit 2 signed transaction (JWS) to be verified and credited.
  public var verify: @Sendable (_ signedTransaction: String) async throws(PaymentsError) -> Answer
  /// Credits or reverses a fake transaction. Only the dev server has this route.
  public var mock:
    @Sendable (_ productID: String, _ transactionID: String, _ kind: MockKind)
      async throws(PaymentsError) -> Answer
  public var ledger: @Sendable () async throws(PaymentsError) -> StampLedger

  public init(
    verify: @escaping @Sendable (String) async throws(PaymentsError) -> Answer,
    mock: @escaping @Sendable (String, String, MockKind) async throws(PaymentsError) -> Answer,
    ledger: @escaping @Sendable () async throws(PaymentsError) -> StampLedger
  ) {
    self.verify = verify
    self.mock = mock
    self.ledger = ledger
  }

  /// A server that is never reached.
  public static let unreachable = PaymentsServer(
    verify: { (_) async throws(PaymentsError) in throw .unavailable },
    mock: { (_, _, _) async throws(PaymentsError) in throw .unavailable },
    ledger: { () async throws(PaymentsError) in throw .unavailable })
}
