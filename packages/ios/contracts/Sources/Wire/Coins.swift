/// Wire form of the contracts `CoinEntryKind`: where a wallet entry came from.
public enum CoinEntryKind: String, Codable, Hashable, Sendable {
  case earn, buy, spend, refund, gift, bonus
}

/// Wire form of the contracts `CoinEntry`: one line of the pair's wallet. `amount` is signed, so a
/// spend is negative. `id` is `<kind>:<source>`; `ref` names the cat entry, item or transaction.
public struct CoinEntry: Codable, Hashable, Sendable {
  public let id: String
  public let kind: CoinEntryKind
  public let amount: Int
  public let ref: String
  public let at: Int64

  public init(id: String, kind: CoinEntryKind, amount: Int, ref: String, at: Int64) {
    self.id = id
    self.kind = kind
    self.amount = amount
    self.ref = ref
    self.at = at
  }
}

/// `GET /v1/coins`: the pair's balance and its wallet entries after `after`, oldest first. Coins
/// are earned on the server from the cat journal, within daily caps; the app never adds any.
public struct CoinsResponse: Codable, Hashable, Sendable {
  public let balance: Int
  public let entries: [CoinEntry]

  public init(balance: Int, entries: [CoinEntry]) {
    self.balance = balance
    self.entries = entries
  }
}

/// `POST /v1/shop/buy`: one item at its catalog price. Repeat `id` on every retry of the same buy.
public struct BuyRequest: Codable, Hashable, Sendable {
  public let id: IdempotencyKey
  public let item: InkId

  public init(id: IdempotencyKey, item: InkId) {
    self.id = id
    self.item = item
  }
}

/// The spend, the balance after it, what it granted, and every ink the pair now owns.
public struct BuyResponse: Codable, Hashable, Sendable {
  public let entry: CoinEntry
  public let balance: Int
  public let granted: [InkId]
  public let owned: [InkId]

  public init(entry: CoinEntry, balance: Int, granted: [InkId], owned: [InkId]) {
    self.entry = entry
    self.balance = balance
    self.granted = granted
    self.owned = owned
  }
}
