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

/// Something the couple did in the app that earns coins, once per ref.
public enum EarnEvent: Codable, Hashable, Sendable {
  case wishReceived(wish: String)
  case dateMatched(idea: String)
  case dateRated(plan: String)
  case listTicked(item: String)
  case momentAdded(moment: String)
  case noteAdded(note: String)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case wish
    case idea
    case plan
    case item
    case moment
    case note
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "WishReceived":
      self = .wishReceived(wish: try container.decode(String.self, forKey: .wish))
    case "DateMatched": self = .dateMatched(idea: try container.decode(String.self, forKey: .idea))
    case "DateRated": self = .dateRated(plan: try container.decode(String.self, forKey: .plan))
    case "ListTicked": self = .listTicked(item: try container.decode(String.self, forKey: .item))
    case "MomentAdded":
      self = .momentAdded(moment: try container.decode(String.self, forKey: .moment))
    case "NoteAdded": self = .noteAdded(note: try container.decode(String.self, forKey: .note))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .wishReceived(let wish):
      try container.encode("WishReceived", forKey: .tag)
      try container.encode(wish, forKey: .wish)
    case .dateMatched(let idea):
      try container.encode("DateMatched", forKey: .tag)
      try container.encode(idea, forKey: .idea)
    case .dateRated(let plan):
      try container.encode("DateRated", forKey: .tag)
      try container.encode(plan, forKey: .plan)
    case .listTicked(let item):
      try container.encode("ListTicked", forKey: .tag)
      try container.encode(item, forKey: .item)
    case .momentAdded(let moment):
      try container.encode("MomentAdded", forKey: .tag)
      try container.encode(moment, forKey: .moment)
    case .noteAdded(let note):
      try container.encode("NoteAdded", forKey: .tag)
      try container.encode(note, forKey: .note)
    }
  }
}

/// `POST /v1/coins/earn`: pays an earn within its daily cap. The same event again answers with the
/// first entry.
public struct EarnRequest: Codable, Hashable, Sendable {
  public let event: EarnEvent
  public let utcOffsetSeconds: Int?

  public init(event: EarnEvent, utcOffsetSeconds: Int?) {
    self.event = event
    self.utcOffsetSeconds = utcOffsetSeconds
  }

  private enum CodingKeys: String, CodingKey {
    case event
    case utcOffsetSeconds
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    event = try container.decode(EarnEvent.self, forKey: .event)
    utcOffsetSeconds = try container.decodeOptionalKey(Int.self, forKey: .utcOffsetSeconds)
  }
}

/// The balance, and the entry: `nil` when the day's cap was already met.
public struct EarnResponse: Codable, Hashable, Sendable {
  public let balance: Int
  public let entry: CoinEntry?

  public init(balance: Int, entry: CoinEntry?) {
    self.balance = balance
    self.entry = entry
  }

  private enum CodingKeys: String, CodingKey {
    case balance
    case entry
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    balance = try container.decode(Int.self, forKey: .balance)
    entry = try container.decodeOptionalKey(CoinEntry.self, forKey: .entry)
  }
}
