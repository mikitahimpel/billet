import Foundation
import Observation
import ProfileInterface
import Wire

// MARK: - Icons

public enum UsTint: String, Codable, CaseIterable, Sendable {
  case honey, blush, sky, sage, lilac, sun, coral

  public var colors: (top: UInt32, bottom: UInt32) {
    switch self {
    case .honey: (0xFFC27D, 0xD9784A)
    case .blush: (0xFFB3C1, 0xE2789A)
    case .sky: (0xA9C6F7, 0x6C89D9)
    case .sage: (0xC2D49A, 0x7C9A5E)
    case .lilac: (0xD2BEEE, 0x9A7BB8)
    case .sun: (0xFFE07A, 0xF0A92E)
    case .coral: (0xFFB197, 0xE0704F)
    }
  }
}

public struct UsGlyph: Codable, Hashable, Sendable {
  public var symbol: String
  public var tint: UsTint

  public init(symbol: String, tint: UsTint) {
    self.symbol = symbol
    self.tint = tint
  }

  public static let palette: [UsGlyph] = [
    .init(symbol: "heart.fill", tint: .blush), .init(symbol: "gift.fill", tint: .coral),
    .init(symbol: "birthday.cake.fill", tint: .sun), .init(symbol: "airplane", tint: .sky),
    .init(symbol: "house.fill", tint: .honey), .init(symbol: "pawprint.fill", tint: .honey),
    .init(symbol: "music.note", tint: .lilac), .init(symbol: "gamecontroller.fill", tint: .sky),
    .init(symbol: "leaf.fill", tint: .sage), .init(symbol: "cup.and.saucer.fill", tint: .coral),
    .init(symbol: "camera.fill", tint: .lilac), .init(symbol: "sparkles", tint: .sun),
    .init(symbol: "moon.stars.fill", tint: .lilac), .init(symbol: "tshirt.fill", tint: .blush),
    .init(symbol: "graduationcap.fill", tint: .sky), .init(symbol: "ticket.fill", tint: .coral),
  ]
}

// MARK: - Lists

public enum ListKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case watch, groceries, travel, food, books, bucket, custom

  public var id: String { rawValue }

  public var defaultTitle: String {
    switch self {
    case .watch: "To watch"
    case .groceries: "Groceries"
    case .travel: "Places to go"
    case .food: "Places to eat"
    case .books: "To read"
    case .bucket: "Bucket list"
    case .custom: "New list"
    }
  }

  public var icon: UsGlyph {
    switch self {
    case .watch: .init(symbol: "popcorn.fill", tint: .coral)
    case .groceries: .init(symbol: "basket.fill", tint: .sage)
    case .travel: .init(symbol: "airplane", tint: .sky)
    case .food: .init(symbol: "fork.knife", tint: .honey)
    case .books: .init(symbol: "book.fill", tint: .lilac)
    case .bucket: .init(symbol: "star.fill", tint: .sun)
    case .custom: .init(symbol: "list.bullet", tint: .blush)
    }
  }

  /// Groceries is a plain checklist; every other list is a "we want to" list whose done items become history.
  public var isChecklist: Bool { self == .groceries }
}

/// What the poster grid draws without asking TMDB.
public struct ItemMedia: Codable, Hashable, Sendable {
  public enum Kind: String, Codable, Sendable { case movie, tv }
  public var kind: Kind
  public var tmdb: Int
  public var year: Int?
  /// A TMDB image file such as `/qJeU7KM4nT2C1WpOrwPcSDGFUWE.jpg`.
  public var posterPath: String?

  public init(kind: Kind, tmdb: Int, year: Int? = nil, posterPath: String? = nil) {
    self.kind = kind
    self.tmdb = tmdb
    self.year = year
    self.posterPath = posterPath
  }
}

public struct ListItem: Identifiable, Codable, Hashable, Sendable {
  public var id = UUID()
  public var text: String
  /// Monogram of the partner who added it.
  public var author: String
  public var added = Date.now
  public var done: Date?
  /// Monogram of the partner who ticked it, when known.
  public var doneBy: String?
  public var quantity: String?
  public var note: String?
  /// Overrides the icon the phone picks from the text.
  public var icon: String?
  /// A store aisle such as `dairy`, for groceries.
  public var aisle: String?
  public var media: ItemMedia?
  /// ISO 3166-1 alpha-2, for places.
  public var country: String?
  /// A city or place in `country`, rather than the country itself.
  public var place = false
  /// The month the pair went, such as `2026-10`.
  public var visitedIn: String?
  public var moments: [UUID] = []
  /// Monograms of the partners who want it.
  public var wants: [String] = []

  public init(
    id: UUID = UUID(), text: String, author: String, added: Date = Date.now, done: Date? = nil,
    doneBy: String? = nil, quantity: String? = nil, note: String? = nil, icon: String? = nil,
    aisle: String? = nil, media: ItemMedia? = nil, country: String? = nil, place: Bool = false,
    visitedIn: String? = nil, moments: [UUID] = [], wants: [String] = []
  ) {
    self.id = id
    self.text = text
    self.author = author
    self.added = added
    self.done = done
    self.doneBy = doneBy
    self.quantity = quantity
    self.note = note
    self.icon = icon
    self.aisle = aisle
    self.media = media
    self.country = country
    self.place = place
    self.visitedIn = visitedIn
    self.moments = moments
    self.wants = wants
  }
}

extension ListItem {
  /// Files from builds before shared lists have no `wants`.
  public nonisolated init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    text = try container.decode(String.self, forKey: .text)
    author = try container.decode(String.self, forKey: .author)
    added = try container.decode(Date.self, forKey: .added)
    done = try container.decodeIfPresent(Date.self, forKey: .done)
    doneBy = try container.decodeIfPresent(String.self, forKey: .doneBy)
    quantity = try container.decodeIfPresent(String.self, forKey: .quantity)
    note = try container.decodeIfPresent(String.self, forKey: .note)
    icon = try container.decodeIfPresent(String.self, forKey: .icon)
    aisle = try container.decodeIfPresent(String.self, forKey: .aisle)
    media = try container.decodeIfPresent(ItemMedia.self, forKey: .media)
    country = try container.decodeIfPresent(String.self, forKey: .country)
    place = try container.decodeIfPresent(Bool.self, forKey: .place) ?? false
    visitedIn = try container.decodeIfPresent(String.self, forKey: .visitedIn)
    moments = try container.decodeIfPresent([UUID].self, forKey: .moments) ?? []
    wants = try container.decodeIfPresent([String].self, forKey: .wants) ?? []
  }
}

public struct UsList: Identifiable, Codable, Hashable, Sendable {
  public var id = UUID()
  public var kind: ListKind
  public var title: String
  public var icon: UsGlyph
  public var items: [ListItem] = []

  public init(
    id: UUID = UUID(), kind: ListKind, title: String, icon: UsGlyph, items: [ListItem] = []
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.icon = icon
    self.items = items
  }

  public var open: [ListItem] { items.filter { $0.done == nil } }
  /// Newest first.
  public var finished: [ListItem] { items.filter { $0.done != nil }.sorted { $0.done! > $1.done! } }
}

// MARK: - Wishlists

/// A title and a day rather than a calendar entry, since each partner's phone keeps its own calendar.
public struct WishOccasion: Codable, Hashable, Sendable {
  public var title: String
  public var date: Date

  public init(title: String, date: Date) {
    self.title = title
    self.date = date
  }

  /// Negative once the day has passed.
  public func daysLeft(from now: Date = .now) -> Int {
    let calendar = Calendar.current
    return calendar.dateComponents(
      [.day], from: calendar.startOfDay(for: now),
      to: calendar.startOfDay(for: date)
    ).day ?? 0
  }
}

/// What the owner wants. It carries nothing about who plans to gift it: that is the giver's `GiftPlan`, so the owner's
/// copy can never spoil the surprise.
public struct WishItem: Identifiable, Codable, Hashable, Sendable {
  public var id = UUID()
  public var owner: String
  public var title: String
  public var link = ""
  public var price = ""
  /// Colour, size, model: whatever the giver needs to get the right one.
  public var note = ""
  /// Pinned to the top of the list.
  public var mostWanted = false
  public var occasion: WishOccasion?
  public var added = Date.now
  /// When the owner said it arrived.
  public var gifted: Date?
  /// Who gave it, filled in when it arrives; until then only the giver knows.
  public var giftedBy: String?
  /// The 5 coins for receiving it were paid, so taking "Got it" back and again pays nothing.
  public var rewarded = false
  /// `reservedBy` from builds before gift plans; `UsStore` moves it into a plan on load and it is never written.
  public var legacyGiver: String?

  private enum CodingKeys: String, CodingKey {
    case id, owner, title, link, price, note, mostWanted, occasion, added, gifted, giftedBy,
      rewarded
  }

  private enum LegacyKeys: String, CodingKey { case want, reservedBy }

  public init(
    id: UUID = UUID(), owner: String, title: String, link: String = "", price: String = "",
    note: String = "",
    mostWanted: Bool = false, added: Date = .now
  ) {
    self.id = id
    self.owner = owner
    self.title = title
    self.link = link
    self.price = price
    self.note = note
    self.mostWanted = mostWanted
    self.added = added
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let legacy = try decoder.container(keyedBy: LegacyKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    owner = try c.decode(String.self, forKey: .owner)
    title = try c.decode(String.self, forKey: .title)
    link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
    price = try c.decodeIfPresent(String.self, forKey: .price) ?? ""
    note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    // Three hearts was the top of the old scale.
    mostWanted =
      try c.decodeIfPresent(Bool.self, forKey: .mostWanted)
      ?? (try legacy.decodeIfPresent(Int.self, forKey: .want) == 3)
    occasion = try c.decodeIfPresent(WishOccasion.self, forKey: .occasion)
    added = try c.decodeIfPresent(Date.self, forKey: .added) ?? .distantPast
    gifted = try c.decodeIfPresent(Date.self, forKey: .gifted)
    giftedBy = try c.decodeIfPresent(String.self, forKey: .giftedBy)
    rewarded = try c.decodeIfPresent(Bool.self, forKey: .rewarded) ?? (gifted != nil)
    legacyGiver = try legacy.decodeIfPresent(String.self, forKey: .reservedBy)
  }
}

/// A partner's secret promise to gift one of the other's wishes. Only the giver ever reads it.
public struct GiftPlan: Codable, Hashable, Sendable {
  public enum Stage: String, Codable, Sendable { case planning, bought }

  public var wishID: UUID
  public var giver: String
  public var stage = Stage.planning

  public init(wishID: UUID, giver: String, stage: Stage = Stage.planning) {
    self.wishID = wishID
    self.giver = giver
    self.stage = stage
  }
}

/// A change to the gifts, for the pair's room to make too while the phone is paired.
public enum GiftChange: Hashable, Sendable {
  case save(WishItem)
  case delete(UUID)
  /// Nil lets the plan go.
  case plan(UUID, GiftPlan.Stage?)
  case received(UUID, Bool)
  case loves(Loves, of: String)
}

/// "Forget-me-nots": what a partner likes, filled in by that partner.
public struct Loves: Codable, Hashable, Sendable {
  public var sizes = ""
  public var flowers = ""
  public var coffee = ""
  public var sweets = ""
  public var allergies = ""
  /// "Please don't": gifts to avoid.
  public var avoid = ""

  public init() {}

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sizes = try c.decodeIfPresent(String.self, forKey: .sizes) ?? ""
    flowers = try c.decodeIfPresent(String.self, forKey: .flowers) ?? ""
    coffee = try c.decodeIfPresent(String.self, forKey: .coffee) ?? ""
    sweets = try c.decodeIfPresent(String.self, forKey: .sweets) ?? ""
    allergies = try c.decodeIfPresent(String.self, forKey: .allergies) ?? ""
    avoid = try c.decodeIfPresent(String.self, forKey: .avoid) ?? ""
  }
}

// MARK: - Calendar

public struct UsEvent: Identifiable, Codable, Hashable, Sendable {
  public var id = UUID()
  public var title: String
  public var icon: UsGlyph
  public var date: Date
  public var yearly = false
  /// nil for shared events, otherwise the partner it belongs to.
  public var owner: String?

  public init(
    id: UUID = UUID(), title: String, icon: UsGlyph, date: Date, yearly: Bool = false,
    owner: String? = nil
  ) {
    self.id = id
    self.title = title
    self.icon = icon
    self.date = date
    self.yearly = yearly
    self.owner = owner
  }
}

/// One row in the "Soon" feed: user events, planned dates and relationship milestones merged together.
public struct Upcoming: Identifiable, Hashable, Sendable {
  public enum Source: Hashable, Sendable {
    case event(UUID)
    case date(UUID)
    case milestone
  }

  public let id: String
  public let title: String
  public let icon: UsGlyph
  public let date: Date
  public let source: Source

  public init(id: String, title: String, icon: UsGlyph, date: Date, source: Source) {
    self.id = id
    self.title = title
    self.icon = icon
    self.date = date
    self.source = source
  }

  public var daysLeft: Int {
    Calendar.current.dateComponents(
      [.day], from: Calendar.current.startOfDay(for: .now),
      to: Calendar.current.startOfDay(for: date)
    ).day ?? 0
  }
}

// MARK: - Dates

public struct DateIdea: Identifiable, Codable, Hashable, Sendable {
  public enum Place: String, Codable, CaseIterable, Sendable {
    case home, city, nature, apart

    public var icon: UsGlyph {
      switch self {
      case .home: .init(symbol: "house.fill", tint: .honey)
      case .city: .init(symbol: "building.2.fill", tint: .sky)
      case .nature: .init(symbol: "leaf.fill", tint: .sage)
      case .apart: .init(symbol: "envelope.fill", tint: .blush)
      }
    }
  }
  public enum Cost: String, Codable, CaseIterable, Sendable {
    case free
    case cheap = "$"
    case nice = "$$"
  }
  public enum Length: String, Codable, CaseIterable, Sendable {
    case hour = "1h"
    case evening, day
  }
  public enum Season: String, Codable, Sendable { case any, spring, summer, autumn, winter }
  /// The card's picture on the API's host, and its average colour, `#RRGGBB`, shown while it loads.
  public struct Art: Codable, Hashable, Sendable {
    public let path: String
    public let color: String

    public init(path: String, color: String) {
      self.path = path
      self.color = color
    }
  }

  public let id: Int
  private let rawTitle: String
  private let rawPitch: String
  public let place: Place
  public let cost: Cost
  public let time: Length
  public let season: Season
  public let art: Art

  public var title: String { ProfileInterface.CatProfile.named(rawTitle) }
  public var pitch: String { ProfileInterface.CatProfile.named(rawPitch) }

  private enum CodingKeys: String, CodingKey {
    case id
    case rawTitle = "title"
    case rawPitch = "pitch"
    case place, cost, time, season, art
  }

  /// The last catalog the server sent, else the one the build ships with. Read once per launch, so a newer
  /// catalog shows from the next one.
  public static let all: [DateIdea] = DateCatalog.saved?.ideas ?? DateCatalog.bundled?.ideas ?? []

  public static func idea(_ id: Int) -> DateIdea? { all.first { $0.id == id } }

  public func inSeason(_ current: Season) -> Bool {
    season == .any || season == current
  }
}

extension DateIdea.Season {
  public static var current: Self {
    switch Calendar.current.component(.month, from: .now) {
    case 3...5: .spring
    case 6...8: .summer
    case 9...11: .autumn
    default: .winter
    }
  }
}

public struct DateFilter: Hashable, Sendable {
  public var places: Set<DateIdea.Place> = []
  public var costs: Set<DateIdea.Cost> = []
  public var lengths: Set<DateIdea.Length> = []

  public init(
    places: Set<DateIdea.Place> = [], costs: Set<DateIdea.Cost> = [],
    lengths: Set<DateIdea.Length> = []
  ) {
    self.places = places
    self.costs = costs
    self.lengths = lengths
  }

  public func allows(_ idea: DateIdea) -> Bool {
    (places.isEmpty || places.contains(idea.place))
      && (costs.isEmpty || costs.contains(idea.cost))
      && (lengths.isEmpty || lengths.contains(idea.time))
  }
}

public struct PlannedDate: Identifiable, Codable, Hashable, Sendable {
  public var id = UUID()
  public var ideaID: Int
  public var date: Date
  public var place = ""
  public var organizer: String
  /// In surprise mode the other partner sees only the date and the hint.
  public var surprise = false
  public var hint = ""
  /// 1...3 hearts after it happened; nil until rated.
  public var rating: Int?
  /// Local reminders a day and an hour before; nil on dates saved before reminders existed.
  public var remind: Bool?
  /// Set when it was marked done with a photo.
  public var momentID: UUID?

  public init(
    id: UUID = UUID(), ideaID: Int, date: Date, place: String = "", organizer: String,
    surprise: Bool = false, hint: String = "", rating: Int? = nil, remind: Bool? = nil,
    momentID: UUID? = nil
  ) {
    self.id = id
    self.ideaID = ideaID
    self.date = date
    self.place = place
    self.organizer = organizer
    self.surprise = surprise
    self.hint = hint
    self.rating = rating
    self.remind = remind
    self.momentID = momentID
  }
}
