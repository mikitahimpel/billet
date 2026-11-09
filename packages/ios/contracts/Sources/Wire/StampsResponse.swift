/// The contract's `PurchasesResponse`.
public struct StampsResponse: Codable, Hashable, Sendable {
  public struct Entry: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
      case purchase
      case refund
    }

    /// `purchase:<transaction>` or `refund:<transaction>`, stable on the server.
    public let id: String
    public let kind: Kind
    public let amount: Int
    public let productId: String
    public let at: String

    public init(id: String, kind: Kind, amount: Int, productId: String, at: String) {
      self.id = id
      self.kind = kind
      self.amount = amount
      self.productId = productId
      self.at = at
    }
  }

  public let balance: Int
  public let entries: [Entry]

  public init(balance: Int, entries: [Entry]) {
    self.balance = balance
    self.entries = entries
  }
}
