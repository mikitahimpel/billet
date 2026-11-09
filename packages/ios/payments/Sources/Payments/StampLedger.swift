public struct StampLedger: Hashable, Sendable {
  public enum Kind: String, Hashable, Sendable {
    case purchase
    case refund
  }

  public struct Entry: Hashable, Sendable, Identifiable {
    /// Stable on the server: `purchase:<transaction>` or `refund:<transaction>`.
    public let id: String
    public let kind: Kind
    /// Positive for a purchase, negative for a refund.
    public let amount: Int
    public let productID: String

    public init(id: String, kind: Kind, amount: Int, productID: String) {
      self.id = id
      self.kind = kind
      self.amount = amount
      self.productID = productID
    }
  }

  public let balance: Int
  public let entries: [Entry]

  public init(balance: Int, entries: [Entry]) {
    self.balance = balance
    self.entries = entries
  }

  public static let empty = StampLedger(balance: 0, entries: [])
}
