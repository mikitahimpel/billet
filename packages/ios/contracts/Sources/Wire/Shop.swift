/// One piece for the cat's room, such as `lamp`.
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

/// A bundle or a week's featured set.
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

/// The server prices it; the app's price is only shown.
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

/// Where a piece stands: `surface` is `floor`, `backWall` or `leftWall`; `u` and `v` are grid cells of 5 cm
/// from the room's middle, `v` being 0 on a wall. `quarterTurns` is 0 to 3, plus 4 for a further 45 degrees.
public struct RoomPlacement: Codable, Hashable, Sendable {
  public let item: RoomItemId
  public let surface: String
  public let u: Int
  public let v: Int
  public let quarterTurns: Int

  public init(item: RoomItemId, surface: String, u: Int, v: Int, quarterTurns: Int) {
    self.item = item
    self.surface = surface
    self.u = u
    self.v = v
    self.quarterTurns = quarterTurns
  }
}

/// `POST /v1/shop/layout`: stands a piece, moves it (the same `Place`) or puts it back (`Unplace`).
public enum LayoutChange: Codable, Hashable, Sendable {
  case place(RoomPlacement)
  case unplace(RoomItemId)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case placement
    case item
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .tag) {
    case "Place": self = .place(try container.decode(RoomPlacement.self, forKey: .placement))
    case "Unplace": self = .unplace(try container.decode(RoomItemId.self, forKey: .item))
    case let tag:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .place(let placement):
      try container.encode("Place", forKey: .tag)
      try container.encode(placement, forKey: .placement)
    case .unplace(let item):
      try container.encode("Unplace", forKey: .tag)
      try container.encode(item, forKey: .item)
    }
  }
}

public struct LayoutRequest: Codable, Hashable, Sendable {
  public let id: IdempotencyKey
  public let change: LayoutChange

  public init(id: IdempotencyKey, change: LayoutChange) {
    self.id = id
    self.change = change
  }
}

/// The room's answer: `applied`, or `duplicate` for an id it already applied; `shop` is the pair after it.
public struct LayoutResponse: Codable, Hashable, Sendable {
  public let result: String
  public let shop: ShopResponse
}

/// `GET /v1/shop`. `inks` starts with the free ink, `items` with the starter pieces. `giftDay`
/// is the pair's local day it last opened the daily gift (`nil` before the first).
public struct ShopResponse: Codable, Hashable, Sendable {
  public let balance: Int
  public let inks: [InkId]
  public let items: [RoomItemId]
  public let wishlist: [RoomItemId]
  public let giftDay: String?
  public let bonuses: [String]
  /// Where the pair stood its pieces; absent from a server before placements.
  public let layout: [RoomPlacement]?
  /// The room's own furniture the pair put away; absent from a server before it could be moved.
  public let stowed: [RoomItemId]?

  public init(
    balance: Int,
    inks: [InkId],
    items: [RoomItemId],
    wishlist: [RoomItemId],
    giftDay: String? = nil,
    bonuses: [String] = [],
    layout: [RoomPlacement]? = nil,
    stowed: [RoomItemId]? = nil
  ) {
    self.balance = balance
    self.inks = inks
    self.items = items
    self.wishlist = wishlist
    self.giftDay = giftDay
    self.bonuses = bonuses
    self.layout = layout
    self.stowed = stowed
  }

  private enum CodingKeys: String, CodingKey {
    case balance, inks, items, wishlist, giftDay, bonuses, layout, stowed
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
    layout = try container.decodeIfPresent([RoomPlacement].self, forKey: .layout)
    stowed = try container.decodeIfPresent([RoomItemId].self, forKey: .stowed)
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

public struct OrderResponse: Codable, Hashable, Sendable {
  public let entry: CoinEntry
  public let shop: ShopResponse

  public init(entry: CoinEntry, shop: ShopResponse) {
    self.entry = entry
    self.shop = shop
  }
}

/// `PUT /v1/shop/wishlist`.
public struct WishRequest: Codable, Hashable, Sendable {
  public let item: RoomItemId
  public let wished: Bool

  public init(item: RoomItemId, wished: Bool) {
    self.item = item
    self.wished = wished
  }
}

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

/// `amount` is 0 for a piece, which `ref` names.
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

public struct ClaimBonusResponse: Codable, Hashable, Sendable {
  public let entry: CoinEntry
  public let shop: ShopResponse

  public init(entry: CoinEntry, shop: ShopResponse) {
    self.entry = entry
    self.shop = shop
  }
}
