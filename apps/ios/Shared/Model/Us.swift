import Foundation
import Observation
import Wire

// MARK: - Icons

nonisolated enum UsTint: String, Codable, CaseIterable {
    case honey, blush, sky, sage, lilac, sun, coral

    var colors: (top: UInt32, bottom: UInt32) {
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

nonisolated struct UsGlyph: Codable, Hashable {
    var symbol: String
    var tint: UsTint

    static let palette: [UsGlyph] = [
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

nonisolated enum ListKind: String, Codable, CaseIterable, Identifiable {
    case watch, groceries, travel, food, books, bucket, custom

    var id: String { rawValue }

    var defaultTitle: String {
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

    var icon: UsGlyph {
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
    var isChecklist: Bool { self == .groceries }
}

/// What the poster grid draws without asking TMDB.
nonisolated struct ItemMedia: Codable, Hashable {
    enum Kind: String, Codable { case movie, tv }
    var kind: Kind
    var tmdb: Int
    var year: Int?
    /// A TMDB image file such as `/qJeU7KM4nT2C1WpOrwPcSDGFUWE.jpg`.
    var posterPath: String?
}

nonisolated struct ListItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    /// Monogram of the partner who added it.
    var author: String
    var added = Date.now
    var done: Date?
    /// Monogram of the partner who ticked it, when known.
    var doneBy: String?
    var quantity: String?
    var note: String?
    /// Overrides the icon the phone picks from the text.
    var icon: String?
    /// A store aisle such as `dairy`, for groceries.
    var aisle: String?
    var media: ItemMedia?
    /// ISO 3166-1 alpha-2, for places.
    var country: String?
    /// A city or place in `country`, rather than the country itself.
    var place = false
    /// The month the pair went, such as `2026-10`.
    var visitedIn: String?
    var moments: [UUID] = []
    /// Monograms of the partners who want it.
    var wants: [String] = []
}

extension ListItem {
    /// Files from builds before shared lists have no `wants`.
    nonisolated init(from decoder: any Decoder) throws {
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

nonisolated struct UsList: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: ListKind
    var title: String
    var icon: UsGlyph
    var items: [ListItem] = []

    var open: [ListItem] { items.filter { $0.done == nil } }
    /// Newest first.
    var finished: [ListItem] { items.filter { $0.done != nil }.sorted { $0.done! > $1.done! } }
}

// MARK: - Wishlists

/// A title and a day rather than a calendar entry, since each partner's phone keeps its own calendar.
nonisolated struct WishOccasion: Codable, Hashable {
    var title: String
    var date: Date

    /// Negative once the day has passed.
    func daysLeft(from now: Date = .now) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: date)).day ?? 0
    }
}

/// What the owner wants. It carries nothing about who plans to gift it: that is the giver's `GiftPlan`, so the owner's
/// copy can never spoil the surprise.
nonisolated struct WishItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var owner: String
    var title: String
    var link = ""
    var price = ""
    /// Colour, size, model: whatever the giver needs to get the right one.
    var note = ""
    /// Pinned to the top of the list.
    var mostWanted = false
    var occasion: WishOccasion?
    var added = Date.now
    /// When the owner said it arrived.
    var gifted: Date?
    /// Who gave it, filled in when it arrives; until then only the giver knows.
    var giftedBy: String?
    /// The 20 coins for receiving it were paid, so taking "Got it" back and again pays nothing.
    var rewarded = false
    /// `reservedBy` from builds before gift plans; `UsStore` moves it into a plan on load and it is never written.
    var legacyGiver: String?

    private enum CodingKeys: String, CodingKey {
        case id, owner, title, link, price, note, mostWanted, occasion, added, gifted, giftedBy, rewarded
    }

    private enum LegacyKeys: String, CodingKey { case want, reservedBy }

    init(id: UUID = UUID(), owner: String, title: String, link: String = "", price: String = "", note: String = "",
         mostWanted: Bool = false, added: Date = .now) {
        self.id = id
        self.owner = owner
        self.title = title
        self.link = link
        self.price = price
        self.note = note
        self.mostWanted = mostWanted
        self.added = added
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        owner = try c.decode(String.self, forKey: .owner)
        title = try c.decode(String.self, forKey: .title)
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        price = try c.decodeIfPresent(String.self, forKey: .price) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        // Three hearts was the top of the old scale.
        mostWanted = try c.decodeIfPresent(Bool.self, forKey: .mostWanted)
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
nonisolated struct GiftPlan: Codable, Hashable {
    enum Stage: String, Codable { case planning, bought }

    var wishID: UUID
    var giver: String
    var stage = Stage.planning
}

/// A change to the gifts, for the pair's room to make too while the phone is paired.
nonisolated enum GiftChange: Hashable {
    case save(WishItem)
    case delete(UUID)
    /// Nil lets the plan go.
    case plan(UUID, GiftPlan.Stage?)
    case received(UUID, Bool)
    case loves(Loves, of: String)
}

/// "Forget-me-nots": what a partner likes, filled in by that partner.
nonisolated struct Loves: Codable, Hashable {
    var sizes = ""
    var flowers = ""
    var coffee = ""
    var sweets = ""
    var allergies = ""
    /// "Please don't": gifts to avoid.
    var avoid = ""

    init() {}

    init(from decoder: Decoder) throws {
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

nonisolated struct UsEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var icon: UsGlyph
    var date: Date
    var yearly = false
    /// nil for shared events, otherwise the partner it belongs to.
    var owner: String?
}

/// One row in the "Soon" feed: user events, planned dates and relationship milestones merged together.
struct Upcoming: Identifiable, Hashable {
    enum Source: Hashable { case event(UUID), date(UUID), milestone }

    let id: String
    let title: String
    let icon: UsGlyph
    let date: Date
    let source: Source

    var daysLeft: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                        to: Calendar.current.startOfDay(for: date)).day ?? 0
    }
}

// MARK: - Dates

nonisolated struct DateIdea: Identifiable, Codable, Hashable {
    enum Place: String, Codable, CaseIterable {
        case home, city, nature, apart

        var icon: UsGlyph {
            switch self {
            case .home: .init(symbol: "house.fill", tint: .honey)
            case .city: .init(symbol: "building.2.fill", tint: .sky)
            case .nature: .init(symbol: "leaf.fill", tint: .sage)
            case .apart: .init(symbol: "envelope.fill", tint: .blush)
            }
        }
    }
    enum Cost: String, Codable, CaseIterable { case free, cheap = "$", nice = "$$" }
    enum Length: String, Codable, CaseIterable { case hour = "1h", evening, day }
    enum Season: String, Codable { case any, spring, summer, autumn, winter }
    /// The card's picture on the API's host, and its average colour, `#RRGGBB`, shown while it loads.
    struct Art: Codable, Hashable {
        let path: String
        let color: String
    }

    let id: Int
    private let rawTitle: String
    private let rawPitch: String
    let place: Place
    let cost: Cost
    let time: Length
    let season: Season
    let art: Art

    var title: String { CatProfile.named(rawTitle) }
    var pitch: String { CatProfile.named(rawPitch) }

    private enum CodingKeys: String, CodingKey {
        case id, rawTitle = "title", rawPitch = "pitch", place, cost, time, season, art
    }

    /// The last catalog the server sent, else the one the build ships with. Read once per launch, so a newer
    /// catalog shows from the next one.
    static let all: [DateIdea] = DateCatalog.saved?.ideas ?? DateCatalog.bundled?.ideas ?? []

    static func idea(_ id: Int) -> DateIdea? { all.first { $0.id == id } }

    func inSeason(_ current: Season) -> Bool {
        season == .any || season == current
    }
}

extension DateIdea.Season {
    static var current: Self {
        switch Calendar.current.component(.month, from: .now) {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
    }
}

struct DateFilter: Hashable {
    var places: Set<DateIdea.Place> = []
    var costs: Set<DateIdea.Cost> = []
    var lengths: Set<DateIdea.Length> = []

    func allows(_ idea: DateIdea) -> Bool {
        (places.isEmpty || places.contains(idea.place))
            && (costs.isEmpty || costs.contains(idea.cost))
            && (lengths.isEmpty || lengths.contains(idea.time))
    }
}

nonisolated struct PlannedDate: Identifiable, Codable, Hashable {
    var id = UUID()
    var ideaID: Int
    var date: Date
    var place = ""
    var organizer: String
    /// In surprise mode the other partner sees only the date and the hint.
    var surprise = false
    var hint = ""
    /// 1...3 hearts after it happened; nil until rated.
    var rating: Int?
    /// Local reminders a day and an hour before; nil on dates saved before reminders existed.
    var remind: Bool?
    /// Set when it was marked done with a photo.
    var momentID: UUID?
}
