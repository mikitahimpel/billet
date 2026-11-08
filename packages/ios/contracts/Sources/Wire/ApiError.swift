public enum ApiError: Codable, Hashable, Sendable {
  case unauthorized
  case invalidRequest
  case unavailable
  case notFound
  case invalidInvite
  case alreadyPaired
  /// The Apple ID is already linked to another account.
  case appleIdInUse
  /// The server would not credit a purchase: its signature, bundle, environment or product.
  case invalidPurchase
  /// A text note in an ink colour the pair has not bought.
  case inkNotOwned(ink: InkId)
  /// A buy that costs more than the pair's balance.
  case notEnoughCoins(needed: Int, have: Int)
  /// A buy of an item the pair already owns.
  case alreadyOwned(itemId: String)
  /// A bonus for a collection with a piece still missing.
  case collectionIncomplete(collection: String)
  /// The day's gift is already open. Come back tomorrow.
  case giftTaken(day: String)
  /// A collection's bonus already paid.
  case bonusTaken(collection: String)
  /// A buy for the cat, such as a treat, before the couple adopted one.
  case catNotAdopted
  /// An order whose price is now above the `expectedPrice` sent; nothing was charged. `price` is
  /// the price now.
  case priceChanged(price: Int)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case ink
    case needed
    case have
    case itemId
    case collection
    case day
    case price
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Unauthorized": self = .unauthorized
    case "InvalidRequest": self = .invalidRequest
    case "Unavailable": self = .unavailable
    case "NotFound": self = .notFound
    case "InvalidInvite": self = .invalidInvite
    case "AlreadyPaired": self = .alreadyPaired
    case "AppleIdInUse": self = .appleIdInUse
    case "InvalidPurchase": self = .invalidPurchase
    case "InkNotOwned": self = .inkNotOwned(ink: try container.decode(InkId.self, forKey: .ink))
    case "NotEnoughCoins":
      self = .notEnoughCoins(
        needed: try container.decode(Int.self, forKey: .needed),
        have: try container.decode(Int.self, forKey: .have))
    case "AlreadyOwned":
      self = .alreadyOwned(itemId: try container.decode(String.self, forKey: .itemId))
    case "CollectionIncomplete":
      self = .collectionIncomplete(
        collection: try container.decode(String.self, forKey: .collection))
    case "GiftTaken": self = .giftTaken(day: try container.decode(String.self, forKey: .day))
    case "BonusTaken":
      self = .bonusTaken(collection: try container.decode(String.self, forKey: .collection))
    case "CatNotAdopted": self = .catNotAdopted
    case "PriceChanged": self = .priceChanged(price: try container.decode(Int.self, forKey: .price))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .unauthorized: try container.encode("Unauthorized", forKey: .tag)
    case .invalidRequest: try container.encode("InvalidRequest", forKey: .tag)
    case .unavailable: try container.encode("Unavailable", forKey: .tag)
    case .notFound: try container.encode("NotFound", forKey: .tag)
    case .invalidInvite: try container.encode("InvalidInvite", forKey: .tag)
    case .alreadyPaired: try container.encode("AlreadyPaired", forKey: .tag)
    case .appleIdInUse: try container.encode("AppleIdInUse", forKey: .tag)
    case .invalidPurchase: try container.encode("InvalidPurchase", forKey: .tag)
    case .inkNotOwned(let ink):
      try container.encode("InkNotOwned", forKey: .tag)
      try container.encode(ink, forKey: .ink)
    case .notEnoughCoins(let needed, let have):
      try container.encode("NotEnoughCoins", forKey: .tag)
      try container.encode(needed, forKey: .needed)
      try container.encode(have, forKey: .have)
    case .alreadyOwned(let itemId):
      try container.encode("AlreadyOwned", forKey: .tag)
      try container.encode(itemId, forKey: .itemId)
    case .collectionIncomplete(let collection):
      try container.encode("CollectionIncomplete", forKey: .tag)
      try container.encode(collection, forKey: .collection)
    case .giftTaken(let day):
      try container.encode("GiftTaken", forKey: .tag)
      try container.encode(day, forKey: .day)
    case .bonusTaken(let collection):
      try container.encode("BonusTaken", forKey: .tag)
      try container.encode(collection, forKey: .collection)
    case .catNotAdopted: try container.encode("CatNotAdopted", forKey: .tag)
    case .priceChanged(let price):
      try container.encode("PriceChanged", forKey: .tag)
      try container.encode(price, forKey: .price)
    }
  }
}
