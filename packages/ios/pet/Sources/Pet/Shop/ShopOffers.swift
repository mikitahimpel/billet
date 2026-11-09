import Foundation

/// When the shop's offers change. Days and weeks are counted in UTC, so the two phones of a pair
/// change their offers at the same moment wherever each of them is.
public enum ShopRotation {
  private static let secondsADay: TimeInterval = 86_400

  /// The UTC day `date` falls on, counted from 1 January 1970.
  public static func day(of date: Date) -> Int {
    Int((date.timeIntervalSince1970 / secondsADay).rounded(.down))
  }

  /// The week `date` falls on, from Monday 00:00 UTC. Day 0 was a Thursday.
  public static func week(of date: Date) -> Int {
    Int((Double(day(of: date) + 3) / 7).rounded(.down))
  }

  /// The next daily change.
  public static func nextDay(after date: Date) -> Date {
    Date(timeIntervalSince1970: Double(day(of: date) + 1) * secondsADay)
  }

  /// The next weekly change.
  public static func nextWeek(after date: Date) -> Date {
    Date(timeIntervalSince1970: (Double((week(of: date) + 1) * 7) - 3) * secondsADay)
  }
}

/// A random sequence that is the same on every phone and every launch for the same seed. Swift's
/// own hashing is salted per launch, so the seed string is hashed with FNV-1a and the sequence is
/// SplitMix64.
public struct StableRandom: RandomNumberGenerator, Sendable {
  private var state: UInt64

  public init(seed: String) {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in seed.utf8 {
      hash ^= UInt64(byte)
      hash &*= 0x0000_0100_0000_01b3
    }
    state = hash
  }

  public mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    var z = state
    z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
    z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
    return z ^ (z >> 31)
  }
}

/// A set of things sold together for less than their sum.
public struct ShopBundle: Identifiable, Hashable, Sendable {
  public let id: String
  public let name: String
  /// One line on what it makes of the room.
  public let blurb: String
  /// What is in it, by shop ID. A piece the catalogue lacks, such as a Labs one with Labs off, is
  /// left out.
  public let itemIDs: [ShopItem.ID]
  /// How much less than the sum it costs, in percent.
  public let discount: Int
  /// Sold once, as a first purchase, and not featured.
  public let isStarter: Bool

  public init(
    id: String, name: String, blurb: String, itemIDs: [ShopItem.ID], discount: Int,
    isStarter: Bool = false
  ) {
    self.id = id
    self.name = name
    self.blurb = blurb
    self.itemIDs = itemIDs
    self.discount = discount
    self.isStarter = isStarter
  }

  /// The starter first.
  public static let all: [ShopBundle] = [
    ShopBundle(
      id: "bundle-starter", name: "Make it yours",
      blurb: "A first few things to make the room feel like the two of you.",
      itemIDs: ["furniture-lantern", "furniture-rug", "style-fairy-candle", "treat-fish"],
      discount: 40, isStarter: true),
    ShopBundle(
      id: "bundle-rainy-evening", name: "Rainy evening set",
      blurb: "Rose curtains, a lamp and a lantern lit, mist on the lake, two mugs of tea.",
      itemIDs: [
        "style-curtains-rose", "furniture-lamp", "furniture-lantern", "style-view-mistyLake",
        "furniture-idol-mugs",
      ],
      discount: 25),
    ShopBundle(
      id: "bundle-reading-nook", name: "Reading nook",
      blurb: "A deep armchair, a full bookcase, a rug and somewhere to put the tea.",
      itemIDs: ["furniture-armchair", "furniture-bookcase", "furniture-rug", "furniture-teatable"],
      discount: 25),
    ShopBundle(
      id: "bundle-green-corner", name: "Green corner",
      blurb: "Plants, a print, forest curtains and a cabin in the woods outside.",
      itemIDs: [
        "furniture-monstera", "furniture-print", "style-curtains-forest", "style-view-forestCabin",
      ],
      discount: 25),
    ShopBundle(
      id: "bundle-cat-heaven", name: "Cat heaven",
      blurb: "Somewhere to climb, somewhere to sleep, and two things to chase.",
      itemIDs: ["furniture-tower", "furniture-donutbed", "furniture-yarn", "furniture-mouse"],
      discount: 25),
  ]
}

public struct ShopDeal: Identifiable, Hashable, Sendable {
  public let item: ShopItem
  public let price: Int
  /// In percent.
  public let discount: Int

  public var id: ShopItem.ID { item.id }
}

/// The day's free gift. The pair's phones offer the same gift on the same day, and each phone can
/// take it once.
public struct DailyGift: Identifiable, Hashable, Sendable {
  public enum Reward: Hashable, Sendable {
    case stamps(Int)
    /// A treat for the cat, by shop ID.
    case item(ShopItem.ID)
  }

  /// The ledger ID the gift is taken under: one a day.
  public let id: String
  public let day: Int
  public let reward: Reward
}

/// What the shop offers today: a bundle for the week, three deals for the day and a free gift. All
/// of it follows from the pair's room, the date and the catalogue, so both phones show the same
/// without asking a server, and each timer runs to a real change.
public struct ShopOffers: Hashable, Sendable {
  public static let dealCount = 3
  /// In percent.
  static let dealDiscounts = [20, 25, 30]
  /// The cheapest item a deal is worth making of.
  static let dealFloor = 8

  public let featured: ShopBundle?
  public let featuredEnds: Date
  public let deals: [ShopDeal]
  /// When the deals and the gift change.
  public let dayEnds: Date
  public let gift: DailyGift
  /// Every bundle for sale beside the featured one.
  public let bundles: [ShopBundle]

  /// - Parameter pair: Something both phones of the pair share and nobody else has, such as the
  ///   room's code. It only seeds the choice.
  public init(pair: String, now: Date, catalog: ShopCatalog) {
    let day = ShopRotation.day(of: now)
    let week = ShopRotation.week(of: now)
    let usable = ShopBundle.all.filter { !$0.items(in: catalog).isEmpty }

    var weekly = StableRandom(seed: "\(pair)|week|\(week)")
    let rotating = usable.filter { !$0.isStarter }
    let featured = rotating.isEmpty ? nil : rotating[Int(weekly.next() % UInt64(rotating.count))]
    self.featured = featured
    featuredEnds = ShopRotation.nextWeek(after: now)
    bundles = usable.filter { $0.id != featured?.id }

    var daily = StableRandom(seed: "\(pair)|day|\(day)")
    let candidates = ShopItem.Shelf.allCases
      .flatMap { catalog.items(on: $0) }
      .filter { $0.price >= Self.dealFloor }
      .sorted { $0.id < $1.id }
    deals = candidates.shuffled(using: &daily).prefix(Self.dealCount).map { item in
      let discount = Self.dealDiscounts[Int(daily.next() % UInt64(Self.dealDiscounts.count))]
      return ShopDeal(item: item, price: item.price * (100 - discount) / 100, discount: discount)
    }
    dayEnds = ShopRotation.nextDay(after: now)

    var giftRoll = StableRandom(seed: "\(pair)|gift|\(day)")
    let treats = catalog.items(in: .treats).sorted { $0.id < $1.id }
    let reward: DailyGift.Reward
    if !treats.isEmpty, giftRoll.next() % 4 == 0 {
      reward = .item(treats[Int(giftRoll.next() % UInt64(treats.count))].id)
    } else {
      reward = .stamps(10 + Int(giftRoll.next() % 3) * 5)
    }
    gift = DailyGift(id: "gift:daily:\(day)", day: day, reward: reward)
  }
}

extension ShopBundle {
  public func items(in catalog: ShopCatalog) -> [ShopItem] {
    itemIDs.compactMap(catalog.anyItem)
  }

  /// The items still to get: those that can only be owned once and already are, are left out
  /// and not charged for.
  public func remaining(in catalog: ShopCatalog, owns: (ShopItem) -> Bool) -> [ShopItem] {
    items(in: catalog).filter { !($0.ownsAtMostOne && owns($0)) }
  }

  public static func sum(of items: [ShopItem]) -> Int {
    items.reduce(0) { $0 + $1.price }
  }

  public func price(of items: [ShopItem]) -> Int {
    Self.sum(of: items) * (100 - discount) / 100
  }
}

extension ShopCatalog {
  /// An item of this catalogue, or a choice of the Style tab sold in the shop, by ID.
  public func anyItem(_ id: ShopItem.ID) -> ShopItem? {
    item(id) ?? RoomStyleItem.all.lazy.compactMap(\.shopItem).first { $0.id == id }
  }
}
