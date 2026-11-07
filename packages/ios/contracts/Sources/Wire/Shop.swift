/// Wire form of the contracts `RoomItemId`: one piece for the cat's room, such as `lamp`.
public struct RoomItemId: Codable, Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// Wire form of the contracts `PieceSetId`: a bundle or a week's featured set.
public struct PieceSetId: Codable, Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// What one order in the shop buys. The server prices it; the app's price is only shown.
public enum ShopOffer: Codable, Hashable, Sendable {
  case ink(InkId)
  case item(RoomItemId)
  case set(PieceSetId)
  case treat

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case ink
    case item
    case set
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Ink":
      self = .ink(try container.decode(InkId.self, forKey: .ink))
    case "Item":
      self = .item(try container.decode(RoomItemId.self, forKey: .item))
    case "Set":
      self = .set(try container.decode(PieceSetId.self, forKey: .set))
    case "Treat":
      self = .treat
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .ink(let ink):
      try container.encode("Ink", forKey: .tag)
      try container.encode(ink, forKey: .ink)
    case .item(let item):
      try container.encode("Item", forKey: .tag)
      try container.encode(item, forKey: .item)
    case .set(let set):
      try container.encode("Set", forKey: .tag)
      try container.encode(set, forKey: .set)
    case .treat:
      try container.encode("Treat", forKey: .tag)
    }
  }
}

/// `GET /v1/shop`: what the pair has. `inks` starts with the free ink and `items` with the starter
/// pieces; `wishlist` is in the order it was wished. `giftDay` is the pair's local day it last
/// opened the daily gift on (`nil` before the first), and `bonuses` the collections paid.
public struct ShopResponse: Codable, Hashable, Sendable {
  public let balance: Int
  public let inks: [InkId]
  public let items: [RoomItemId]
  public let wishlist: [RoomItemId]
  public let giftDay: String?
  public let bonuses: [String]

  public init(
    balance: Int,
    inks: [InkId],
    items: [RoomItemId],
    wishlist: [RoomItemId],
    giftDay: String? = nil,
    bonuses: [String] = []
  ) {
    self.balance = balance
    self.inks = inks
    self.items = items
    self.wishlist = wishlist
    self.giftDay = giftDay
    self.bonuses = bonuses
  }

  private enum CodingKeys: String, CodingKey {
    case balance, inks, items, wishlist, giftDay, bonuses
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    balance = try container.decode(Int.self, forKey: .balance)
    inks = try container.decode([InkId].self, forKey: .inks)
    items = try container.decode([RoomItemId].self, forKey: .items)
    wishlist = try container.decode([RoomItemId].self, forKey: .wishlist)
    giftDay = try container.decodeOptionalKey(String.self, forKey: .giftDay)
    // A server from before collection bonuses sends none.
    bonuses = try container.decodeIfPresent([String].self, forKey: .bonuses) ?? []
  }
}

/// `POST /v1/shop/orders`. Repeat `id` on every retry of the same order. `utcOffsetSeconds` is the
/// phone's clock, so a piece is priced at the deal of the pair's local day.
public struct OrderRequest: Codable, Hashable, Sendable {
  public let id: IdempotencyKey
  public let offer: ShopOffer
  /// The price the buyer saw. A server price above it is refused with `priceChanged`; a lower one
  /// is charged.
  public let expectedPrice: Int?
  public let utcOffsetSeconds: Int?

  public init(
    id: IdempotencyKey, offer: ShopOffer, expectedPrice: Int? = nil, utcOffsetSeconds: Int? = nil
  ) {
    self.id = id
    self.offer = offer
    self.expectedPrice = expectedPrice
    self.utcOffsetSeconds = utcOffsetSeconds
  }

  private enum CodingKeys: String, CodingKey {
    case id, offer, expectedPrice, utcOffsetSeconds
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(IdempotencyKey.self, forKey: .id)
    offer = try container.decode(ShopOffer.self, forKey: .offer)
    expectedPrice = try container.decodeOptionalKey(Int.self, forKey: .expectedPrice)
    utcOffsetSeconds = try container.decodeOptionalKey(Int.self, forKey: .utcOffsetSeconds)
  }
}

/// The spend, and the pair after it.
public struct OrderResponse: Codable, Hashable, Sendable {
  public let entry: CoinEntry
  public let shop: ShopResponse

  public init(entry: CoinEntry, shop: ShopResponse) {
    self.entry = entry
    self.shop = shop
  }
}

/// `PUT /v1/shop/wishlist`: adds a piece to the pair's wishlist, or takes it off.
public struct WishRequest: Codable, Hashable, Sendable {
  public let item: RoomItemId
  public let wished: Bool

  public init(item: RoomItemId, wished: Bool) {
    self.item = item
    self.wished = wished
  }
}

/// The day's free gift: coins, or a piece the pair didn't own.
public enum GiftReward: Codable, Hashable, Sendable {
  case coins(Int)
  case item(RoomItemId)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case coins
    case item
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Coins": self = .coins(try container.decode(Int.self, forKey: .coins))
    case "Item": self = .item(try container.decode(RoomItemId.self, forKey: .item))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .coins(let coins):
      try container.encode("Coins", forKey: .tag)
      try container.encode(coins, forKey: .coins)
    case .item(let item):
      try container.encode("Item", forKey: .tag)
      try container.encode(item, forKey: .item)
    }
  }
}

/// `POST /v1/shop/gift`: opens the day's gift, once a day for the pair. `utcOffsetSeconds` is the
/// phone's clock; without it the server counts the day on the cat's clock, else UTC.
public struct OpenGiftRequest: Codable, Hashable, Sendable {
  public let utcOffsetSeconds: Int?

  public init(utcOffsetSeconds: Int? = nil) {
    self.utcOffsetSeconds = utcOffsetSeconds
  }

  private enum CodingKeys: String, CodingKey {
    case utcOffsetSeconds
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    utcOffsetSeconds = try container.decodeOptionalKey(Int.self, forKey: .utcOffsetSeconds)
  }
}

/// The gift's entry (amount 0 for a piece, which `ref` names), what it gave, and the pair after.
public struct OpenGiftResponse: Codable, Hashable, Sendable {
  public let entry: CoinEntry
  public let reward: GiftReward
  public let shop: ShopResponse

  public init(entry: CoinEntry, reward: GiftReward, shop: ShopResponse) {
    self.entry = entry
    self.reward = reward
    self.shop = shop
  }
}

/// `POST /v1/shop/bonus`: collects a complete collection's bonus, such as `cozy-autumn`, once.
public struct ClaimBonusRequest: Codable, Hashable, Sendable {
  public let collection: String

  public init(collection: String) {
    self.collection = collection
  }
}

/// The bonus entry, and the pair after it.
public struct ClaimBonusResponse: Codable, Hashable, Sendable {
  public let entry: CoinEntry
  public let shop: ShopResponse

  public init(entry: CoinEntry, shop: ShopResponse) {
    self.entry = entry
    self.shop = shop
  }
}
