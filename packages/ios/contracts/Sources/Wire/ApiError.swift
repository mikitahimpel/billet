public enum ApiError: Codable, Hashable, Sendable {
  case unauthorized
  case invalidRequest
  case unavailable
  case notFound
  case invalidInvite
  case alreadyPaired
  case appleIdInUse
  /// Its signature, bundle, environment or product was refused.
  case invalidPurchase
  case inkNotOwned(ink: InkId)
  case notEnoughCoins(needed: Int, have: Int)
  case alreadyOwned(itemId: String)
  case collectionIncomplete(collection: String)
  case giftTaken(day: String)
  case bonusTaken(collection: String)
  /// Before the couple adopted a cat.
  case catNotAdopted
  /// Alive, too short, out for longer than a day, or in cooldown.
  case streakNotRestorable
  /// Nothing was charged; `price` is the price now.
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
    case "StreakNotRestorable": self = .streakNotRestorable
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
    case .streakNotRestorable: try container.encode("StreakNotRestorable", forKey: .tag)
    case .priceChanged(let price):
      try container.encode("PriceChanged", forKey: .tag)
      try container.encode(price, forKey: .price)
    }
  }
}
