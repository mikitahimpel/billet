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
/// pieces; `wishlist` is in the order it was wished.
public struct ShopResponse: Codable, Hashable, Sendable {
  public let balance: Int
  public let inks: [InkId]
  public let items: [RoomItemId]
  public let wishlist: [RoomItemId]

  public init(balance: Int, inks: [InkId], items: [RoomItemId], wishlist: [RoomItemId]) {
    self.balance = balance
    self.inks = inks
    self.items = items
    self.wishlist = wishlist
  }
}

/// `POST /v1/shop/orders`. Repeat `id` on every retry of the same order.
public struct OrderRequest: Codable, Hashable, Sendable {
  public let id: IdempotencyKey
  public let offer: ShopOffer

  public init(id: IdempotencyKey, offer: ShopOffer) {
    self.id = id
    self.offer = offer
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
