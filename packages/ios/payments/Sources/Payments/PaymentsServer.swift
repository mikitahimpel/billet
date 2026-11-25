/// Closures over plain values, so this module needs no networking.
public struct PaymentsServer: Sendable {
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

    /// Under the entry ID the server's ledger uses.
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

  public enum MockPlusKind: String, Hashable, Sendable, CaseIterable {
    case subscribe, renew, cancel, fail, expire, refund
  }

  /// Takes a StoreKit 2 signed transaction (JWS).
  public var verify: @Sendable (_ signedTransaction: String) async throws(PaymentsError) -> Answer
  /// Only the dev server has this route.
  public var mock:
    @Sendable (_ productID: String, _ transactionID: String, _ kind: MockKind)
      async throws(PaymentsError) -> Answer
  public var ledger: @Sendable () async throws(PaymentsError) -> StampLedger
  /// Binds a Plus transaction (JWS), with its renewal info (JWS) when there is one, to the caller.
  public var subscribe:
    @Sendable (_ signedTransaction: String, _ signedRenewalInfo: String?)
      async throws(PaymentsError) -> Void
  /// Only the dev server has this route.
  public var mockPlus:
    @Sendable (_ plan: PlusCatalog.Plan, _ transactionID: String, _ kind: MockPlusKind)
      async throws(PaymentsError) -> Void

  public init(
    verify: @escaping @Sendable (String) async throws(PaymentsError) -> Answer,
    mock: @escaping @Sendable (String, String, MockKind) async throws(PaymentsError) -> Answer,
    ledger: @escaping @Sendable () async throws(PaymentsError) -> StampLedger,
    subscribe: @escaping @Sendable (String, String?) async throws(PaymentsError) -> Void = {
      (_, _) async throws(PaymentsError) in throw .unavailable
    },
    mockPlus:
      @escaping @Sendable (PlusCatalog.Plan, String, MockPlusKind) async throws(PaymentsError) ->
      Void = { (_, _, _) async throws(PaymentsError) in throw .unavailable }
  ) {
    self.verify = verify
    self.mock = mock
    self.ledger = ledger
    self.subscribe = subscribe
    self.mockPlus = mockPlus
  }

  public static let unreachable = PaymentsServer(
    verify: { (_) async throws(PaymentsError) in throw .unavailable },
    mock: { (_, _, _) async throws(PaymentsError) in throw .unavailable },
    ledger: { () async throws(PaymentsError) in throw .unavailable })
}
