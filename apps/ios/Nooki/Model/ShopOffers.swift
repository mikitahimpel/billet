import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import ProfileInterface
import ShopInterface
import UsInterface

/// How rare a piece is. Only a frame and a label: every item is bought directly, never drawn at random.
enum ShopRarity: String, CaseIterable, Codable {
    case common, rare, epic, legendary

    var title: String {
        switch self {
        case .common: "Common"
        case .rare: "Rare"
        case .epic: "Epic"
        case .legendary: "Legendary"
        }
    }
}

struct DailyDeal: Hashable {
    let itemID: String
    /// 0.2 is 20% off.
    let discount: Double

    /// Rounded to 5 coins, so a deal price reads cleanly.
    func price(of item: ShopItem) -> Int {
        ShopOffers.roundToFive(Double(item.price) * (1 - discount))
    }
}

/// Pieces sold together for less than their sum: the week's featured set and the bundles.
protocol PieceSet {
    var id: String { get }
    var name: String { get }
    var blurb: String { get }
    var itemIDs: [String] { get }
    /// Share of the pieces' sum the couple pays, e.g. 0.5 for half.
    var share: Double { get }
}

/// The week's hero offer: a set of items for less than their sum.
struct FeaturedOffer: PieceSet, Hashable {
    let id: String
    let name: String
    let blurb: String
    let itemIDs: [String]
    /// Share of the set's sum the couple pays, e.g. 0.5 for half.
    let share: Double
    /// When the next featured set replaces it: Monday at local midnight.
    let endsAt: Date
}

/// A themed set that stays in the Shop, priced below the sum of its pieces.
struct ShopBundle: PieceSet, Hashable {
    let id: String
    let name: String
    let blurb: String
    let itemIDs: [String]
    let share: Double
}

/// The free gift for the day: coins, or an item the couple doesn't own yet.
typealias GiftReward = ShopInterface.GiftReward

/// The Shop's rotations. Everything is a pure function of the pair and the local date, so both partners' phones show
/// the same deals and gift without asking anyone, and every countdown ends at a real change. The server runs the same
/// functions (`@billet/contracts-domain/shop`) and charges by them; `shop-offers.json` holds both to it.
struct ShopOffers {
    /// The pair id, the same for both partners and the server.
    let pairSeed: String
    var calendar = Calendar.current

    static let dealCount = 4

    /// Items that can be a deal, with their discount; the day draws `dealCount` of them.
    static let dealPool: [(id: String, discount: Double)] = [
        ("teatable", 0.25), ("yarn", 0.3), ("lantern", 0.2), ("bookcase", 0.2),
        ("mouse", 0.3), ("lamp", 0.25), ("donutbed", 0.2), ("monstera", 0.3), ("print", 0.25),
    ]

    /// Weekly featured sets, in turn.
    static let featuredSets: [(id: String, name: String, blurb: String, itemIDs: [String])] = [
        ("rainy-evening", "Rainy Evening", "Lamp, armchair and a sunset print", ["lamp", "armchair", "print"]),
        ("nap-time", "Nap Time", "Donut bed, woven rug and a mushroom lamp", ["donutbed", "rug", "lamp"]),
        ("tea-for-two", "Tea for Two", "Tea table, monstera and a lantern", ["teatable", "monstera", "lantern"]),
    ]
    static let featuredShare = 0.5

    /// Bundles that stay in the Shop; unlike the featured set they don't rotate.
    static var bundles: [ShopBundle] { [
        ShopBundle(id: "mochi-playday", name: "\(CatProfile.name())'s Playday", blurb: "Yarn, a toy mouse and the cat tower",
                   itemIDs: ["yarn", "mouse", "tower"], share: 0.7),
        ShopBundle(id: "reading-nook", name: "Reading Nook", blurb: "Bookcase, armchair and a mushroom lamp",
                   itemIDs: ["bookcase", "armchair", "lamp"], share: 0.75),
        ShopBundle(id: "window-glow", name: "Window Glow", blurb: "Paper lantern, monstera and a sunset print",
                   itemIDs: ["lantern", "monstera", "print"], share: 0.75),
    ] }

    /// Gift coins are 20, 30 or 40; one day in four it's a small item instead.
    static let giftCoins = [20, 30, 40]
    static let giftItems = ["mouse", "yarn", "monstera"]

    // MARK: Rotations

    /// Local midnight after `date`: when the deals and the gift change.
    func nextDay(after date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86_400)
    }

    /// The next Monday at local midnight: when the featured set changes.
    func nextWeek(after date: Date) -> Date {
        let monday = DateComponents(hour: 0, minute: 0, second: 0, weekday: 2)
        return calendar.nextDate(after: date, matching: monday, matchingPolicy: .nextTime) ?? nextDay(after: date)
    }

    // MARK: Offers

    func deals(on date: Date) -> [DailyDeal] {
        var rng = SeededRandom(seed: Self.hash("\(pairSeed)|deals|\(dayKey(date))"))
        var pool = Self.dealPool
        var picked: [DailyDeal] = []
        while picked.count < Self.dealCount, !pool.isEmpty {
            let entry = pool.remove(at: Int(rng.next() % UInt64(pool.count)))
            picked.append(DailyDeal(itemID: entry.id, discount: entry.discount))
        }
        return picked
    }

    func deal(for itemID: String, on date: Date) -> DailyDeal? {
        deals(on: date).first { $0.itemID == itemID }
    }

    func featured(on date: Date) -> FeaturedOffer {
        let index = mondayWeek(of: date) % Self.featuredSets.count
        let set = Self.featuredSets[index]
        return FeaturedOffer(id: set.id, name: set.name, blurb: set.blurb, itemIDs: set.itemIDs,
                             share: Self.featuredShare, endsAt: nextWeek(after: date))
    }

    /// An item already owned turns into coins.
    func gift(on date: Date, owned: Set<String>) -> GiftReward {
        var rng = SeededRandom(seed: Self.hash("\(pairSeed)|gift|\(dayKey(date))"))
        let roll = rng.next()
        if roll % 4 == 0 {
            let id = Self.giftItems[Int((roll / 4) % UInt64(Self.giftItems.count))]
            if !owned.contains(id) { return .item(id) }
        }
        return .coins(Self.giftCoins[Int(rng.next() % UInt64(Self.giftCoins.count))])
    }

    // MARK: Prices

    /// What the couple pays for a set: its share of the pieces they don't own yet, next to those pieces' sum. Nil
    /// once they own them all.
    static func price(of set: some PieceSet, owned: Set<String>) -> (price: Int, sum: Int)? {
        let missing = set.itemIDs.filter { !owned.contains($0) }.compactMap(Catalog.item)
        guard !missing.isEmpty else { return nil }
        let sum = missing.reduce(0) { $0 + $1.price }
        return (roundToFive(Double(sum) * set.share), sum)
    }

    static func roundToFive(_ value: Double) -> Int {
        Int((value / 5).rounded()) * 5
    }

    // MARK: Seeding

    /// Weeks counted from Monday 2024-01-01, local time, so the set always changes on Monday, where the countdown
    /// ends, whatever weekday the locale's calendar starts its weeks on.
    func mondayWeek(of date: Date) -> Int {
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)) ?? .distantPast
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        return max(0, days) / 7
    }

    /// The local calendar day, so a deal lasts the couple's own day.
    func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// FNV-1a: stable across launches and devices, unlike `Hasher`.
    static func hash(_ text: String) -> UInt64 {
        text.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}

/// SplitMix64, seeded from the pair and the day.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
