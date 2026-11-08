import Foundation

/// What draws a shop item: a model or image the app bundles under `id`, or a picture the admin
/// uploaded, served at `/v1/shop/art/<key>`.
public enum ShopAsset: Codable, Hashable, Sendable {
  case bundled(id: String)
  case picture(key: String)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case id
    case key
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Bundled": self = .bundled(id: try container.decode(String.self, forKey: .id))
    case "Picture": self = .picture(key: try container.decode(String.self, forKey: .key))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .bundled(let id):
      try container.encode("Bundled", forKey: .tag)
      try container.encode(id, forKey: .id)
    case .picture(let key):
      try container.encode("Picture", forKey: .tag)
      try container.encode(key, forKey: .key)
    }
  }
}

/// A price that holds from `from` up to, not including, `until` (epoch milliseconds).
public struct ShopSale: Codable, Hashable, Sendable {
  public let price: Int
  public let from: Int
  public let until: Int

  public init(price: Int, from: Int, until: Int) {
    self.price = price
    self.from = from
    self.until = until
  }
}

/// An item's place in the daily-deals draw: `discount` 0.25 is 25% off, `order` its place in the
/// pool the draw takes from.
public struct ShopDeal: Codable, Hashable, Sendable {
  public let discount: Double
  public let order: Int

  public init(discount: Double, order: Int) {
    self.discount = discount
    self.order = order
  }
}

/// Wire form of the contracts `ShopCatalogItem`. `kind` and `section` are open strings: an app skips
/// a kind it does not know. `name` and `blurb` may hold `{cat}`.
public struct ShopCatalogItem: Codable, Hashable, Sendable {
  public enum Rarity: String, Codable, Hashable, Sendable, CaseIterable {
    case common, rare, epic, legendary
  }

  public let id: String
  public let kind: String
  public let name: String
  public let blurb: String?
  public let mood: String?
  public let rarity: Rarity
  public let price: Int
  public let sale: ShopSale?
  public let deal: ShopDeal?
  public let section: String
  public let sortOrder: Int
  public let plus: Bool?
  public let isNew: Bool?
  public let asset: ShopAsset
  public let minBuild: Int?

  public init(
    id: String, kind: String, name: String, blurb: String? = nil, mood: String? = nil,
    rarity: Rarity, price: Int, sale: ShopSale? = nil, deal: ShopDeal? = nil, section: String,
    sortOrder: Int, plus: Bool? = nil, isNew: Bool? = nil, asset: ShopAsset, minBuild: Int? = nil
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.blurb = blurb
    self.mood = mood
    self.rarity = rarity
    self.price = price
    self.sale = sale
    self.deal = deal
    self.section = section
    self.sortOrder = sortOrder
    self.plus = plus
    self.isNew = isNew
    self.asset = asset
    self.minBuild = minBuild
  }

  private enum CodingKeys: String, CodingKey {
    case id, kind, name, blurb, mood, rarity, price, sale, deal, section, sortOrder, plus, isNew
    case asset, minBuild
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    kind = try container.decode(String.self, forKey: .kind)
    name = try container.decode(String.self, forKey: .name)
    blurb = try container.decodeOptionalKey(String.self, forKey: .blurb)
    mood = try container.decodeOptionalKey(String.self, forKey: .mood)
    rarity = try container.decode(Rarity.self, forKey: .rarity)
    price = try container.decode(Int.self, forKey: .price)
    sale = try container.decodeOptionalKey(ShopSale.self, forKey: .sale)
    deal = try container.decodeOptionalKey(ShopDeal.self, forKey: .deal)
    section = try container.decode(String.self, forKey: .section)
    sortOrder = try container.decode(Int.self, forKey: .sortOrder)
    plus = try container.decodeOptionalKey(Bool.self, forKey: .plus)
    isNew = try container.decodeOptionalKey(Bool.self, forKey: .isNew)
    asset = try container.decode(ShopAsset.self, forKey: .asset)
    minBuild = try container.decodeOptionalKey(Int.self, forKey: .minBuild)
  }

  /// What the item costs at `date`: its sale price inside the sale's window, else its price.
  public func effectivePrice(at date: Date) -> Int {
    let millis = Int(date.timeIntervalSince1970 * 1000)
    guard let sale, millis >= sale.from, millis < sale.until else { return price }
    return sale.price
  }
}

/// `GET /v1/shop/catalog`: the active items, in shelf order. `version` is the response's ETag. An
/// item that does not decode (a rarity this app does not know) is left out, not an error.
public struct ShopCatalogResponse: Codable, Hashable, Sendable {
  public let version: String
  public let items: [ShopCatalogItem]

  public init(version: String, items: [ShopCatalogItem]) {
    self.version = version
    self.items = items
  }

  private enum CodingKeys: String, CodingKey {
    case version, items
  }

  private struct Skipped: Decodable {
    init(from decoder: any Decoder) throws {}
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(String.self, forKey: .version)
    var list = try container.nestedUnkeyedContainer(forKey: .items)
    var decoded: [ShopCatalogItem] = []
    while !list.isAtEnd {
      if let item = try? list.decode(ShopCatalogItem.self) {
        decoded.append(item)
      } else {
        _ = try list.decode(Skipped.self)
      }
    }
    items = decoded
  }
}
