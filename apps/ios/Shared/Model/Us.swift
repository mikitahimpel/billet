import Foundation
import Observation

// MARK: - Icons

/// Soft gradient tints for icon tiles, matching the app's honey and blush palette.
nonisolated enum UsTint: String, Codable, CaseIterable {
    case honey, blush, sky, sage, lilac, sun, coral

    /// Top and bottom of the tile gradient.
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

/// An SF Symbol on a tinted tile; replaces emoji everywhere on the Us tab.
nonisolated struct UsGlyph: Codable, Hashable {
    var symbol: String
    var tint: UsTint

    /// Choices offered for custom lists and calendar events.
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

nonisolated struct ListItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    /// Monogram of the partner who added it.
    var author: String
    var added = Date.now
    var done: Date?
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

nonisolated struct WishItem: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Whose wish it is.
    var owner: String
    var title: String
    var link = ""
    var price = ""
    /// 1...3 hearts.
    var want = 2
    /// The partner who secretly promised to gift it. The owner only sees that someone did, never what.
    var reservedBy: String?
    var gifted: Date?
}

/// "Forget-me-nots": what a partner likes, filled in by that partner.
nonisolated struct Loves: Codable, Hashable {
    var sizes = ""
    var flowers = ""
    var coffee = ""
    var sweets = ""
    var allergies = ""
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

struct DateIdea: Identifiable, Codable, Hashable {
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
    /// The card's background picture, `DateScene-<scene>` in the app's asset catalog.
    enum Scene: String, Codable, CaseIterable {
        case movie, kitchen, cozy, games, craft, cafe, city, nature, night, winter, apart, plans

        var imageName: String { "DateScene-\(rawValue)" }
    }

    let id: Int
    private let rawTitle: String
    private let rawPitch: String
    let place: Place
    let cost: Cost
    let time: Length
    let season: Season
    let scene: Scene

    var title: String { CatProfile.named(rawTitle) }
    var pitch: String { CatProfile.named(rawPitch) }

    private enum CodingKeys: String, CodingKey {
        case id, rawTitle = "title", rawPitch = "pitch", place, cost, time, season, scene
    }

    static let all: [DateIdea] = {
        guard let url = Bundle.main.url(forResource: "DateIdeas", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DateIdea].self, from: data)) ?? []
    }()

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
    /// Partner who organizes it.
    var organizer: String
    /// In surprise mode the other partner sees only the date and the hint.
    var surprise = false
    var hint = ""
    /// 1...3 hearts after it happened; nil until rated.
    var rating: Int?
}

// MARK: - Store

/// Everything on the Us tab. Local-only JSON in the app group for now (docs/together-concept.md, section 6), shared
/// with the widgets; both partners share this device's copy until sync lands.
@Observable
final class UsStore {
    private(set) var lists: [UsList] = []
    private(set) var wishes: [WishItem] = []
    private(set) var loves: [String: Loves] = [:]
    private(set) var events: [UsEvent] = []
    private(set) var planned: [PlannedDate] = []
    /// Per partner: idea id -> liked (true) or skipped (false).
    private(set) var swipes: [String: [Int: Bool]] = [:]

    /// Where the coins the couple earns here go; HomeState passes its own.
    @ObservationIgnored let wallet: WalletStore

    private let file: String

    private nonisolated struct Snapshot: Codable {
        var lists: [UsList]
        var wishes: [WishItem]
        var loves: [String: Loves]
        var events: [UsEvent]
        var planned: [PlannedDate]
        var swipes: [String: [Int: Bool]]
    }

    init(wallet: WalletStore = WalletStore(), file: String = "Us/us.json") {
        self.wallet = wallet
        self.file = file
        reload()
    }

    /// Picks up what the widgets changed while the app was away.
    func reload() {
        if let saved = SharedFile.read(Snapshot.self, from: file) {
            lists = saved.lists
            wishes = saved.wishes
            loves = saved.loves
            events = saved.events
            planned = saved.planned
            swipes = saved.swipes
        } else {
            // Starter lists are empty containers, not fake content.
            lists = [.watch, .groceries, .travel].map { UsList(kind: $0, title: $0.defaultTitle, icon: $0.icon) }
        }
    }

    private func save() {
        SharedFile.write(Snapshot(lists: lists, wishes: wishes, loves: loves, events: events, planned: planned, swipes: swipes),
                         to: file)
    }

    // MARK: Lists

    func list(_ id: UUID) -> UsList? { lists.first { $0.id == id } }

    @discardableResult
    func addList(kind: ListKind, title: String, icon: UsGlyph) -> UsList {
        let list = UsList(kind: kind, title: title, icon: icon)
        lists.append(list)
        save()
        return list
    }

    func renameList(_ id: UUID, title: String, icon: UsGlyph) {
        guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[i].title = title
        lists[i].icon = icon
        save()
    }

    func deleteList(_ id: UUID) {
        lists.removeAll { $0.id == id }
        save()
    }

    func addItem(_ text: String, to listID: UUID, author: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let i = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[i].items.insert(ListItem(text: text, author: author), at: 0)
        save()
    }

    func toggleItem(_ itemID: UUID, in listID: UUID) {
        guard let item = list(listID)?.items.first(where: { $0.id == itemID }) else { return }
        setItem(itemID, in: listID, done: item.done == nil)
    }

    /// Ticking a "we want to" item earns 5 coins, at most 3 times a day; groceries earn nothing.
    func setItem(_ itemID: UUID, in listID: UUID, done: Bool) {
        guard let l = lists.firstIndex(where: { $0.id == listID }),
              let i = lists[l].items.firstIndex(where: { $0.id == itemID }),
              (lists[l].items[i].done != nil) != done else { return }
        lists[l].items[i].done = done ? .now : nil
        if done && !lists[l].kind.isChecklist { wallet.update { $0.tickList() } }
        save()
    }

    func deleteItem(_ itemID: UUID, in listID: UUID) {
        guard let l = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[l].items.removeAll { $0.id == itemID }
        save()
    }

    /// Groceries: drop everything already bought.
    func clearDone(in listID: UUID) {
        guard let l = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[l].items.removeAll { $0.done != nil }
        save()
    }

    // MARK: Wishlists

    func wishes(of owner: String) -> [WishItem] {
        wishes.filter { $0.owner == owner && $0.gifted == nil }.sorted { $0.want > $1.want }
    }

    func gifted(to owner: String) -> [WishItem] {
        wishes.filter { $0.owner == owner && $0.gifted != nil }.sorted { $0.gifted! > $1.gifted! }
    }

    func upsertWish(_ wish: WishItem) {
        if let i = wishes.firstIndex(where: { $0.id == wish.id }) { wishes[i] = wish } else { wishes.append(wish) }
        save()
    }

    func deleteWish(_ id: UUID) {
        wishes.removeAll { $0.id == id }
        save()
    }

    /// Secret pick: the giver promises to gift it; calling again releases it.
    func toggleReserve(_ id: UUID, by giver: String) {
        guard let i = wishes.firstIndex(where: { $0.id == id }), wishes[i].owner != giver else { return }
        wishes[i].reservedBy = wishes[i].reservedBy == nil ? giver : nil
        save()
    }

    /// The owner confirms the gift arrived: it moves to "Gifted" and the couple earns 20 coins.
    func markReceived(_ id: UUID) {
        guard let i = wishes.firstIndex(where: { $0.id == id }), wishes[i].gifted == nil else { return }
        wishes[i].gifted = .now
        wallet.earn(20)
        save()
    }

    func loves(of partner: String) -> Loves { loves[partner] ?? Loves() }

    func setLoves(_ value: Loves, for partner: String) {
        loves[partner] = value
        save()
    }

    // MARK: Calendar

    func upsertEvent(_ event: UsEvent) {
        if let i = events.firstIndex(where: { $0.id == event.id }) { events[i] = event } else { events.append(event) }
        save()
    }

    func deleteEvent(_ id: UUID) {
        events.removeAll { $0.id == id }
        save()
    }

    /// Next occurrence of every event, planned date and milestone from `now`'s day on, soonest first.
    func upcoming(togetherSince start: Date, limit: Int = 30, from now: Date = .now) -> [Upcoming] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var rows: [Upcoming] = []

        for e in events {
            var n = 0
            var date = e.date
            if e.yearly {
                while cal.startOfDay(for: date) < today {
                    n += 1
                    date = cal.date(byAdding: .year, value: n, to: e.date) ?? date
                }
            }
            guard cal.startOfDay(for: date) >= today else { continue }
            rows.append(row(e, on: date, id: e.id.uuidString))
        }

        for p in planned where p.rating == nil && cal.startOfDay(for: p.date) >= today {
            rows.append(row(p))
        }

        // Day-count milestones, plus the next month anniversary in the first year and the next yearly one.
        let future = { (row: Upcoming) in row.date >= today }
        let (days, months, years) = milestones(since: start)
        rows += days.filter(future)
        rows += [months.first(where: future), years.first(where: future)].compactMap { $0 }

        return Array(rows.sorted { $0.date < $1.date }.prefix(limit))
    }

    /// Every event, planned date and milestone that falls in `interval`, past ones too; yearly events once per year.
    func occurrences(togetherSince start: Date, in interval: DateInterval) -> [Upcoming] {
        let cal = Calendar.current
        let contains = { (date: Date) in date >= interval.start && date < interval.end }
        var rows: [Upcoming] = []

        for e in events {
            guard e.yearly else {
                if contains(e.date) { rows.append(row(e, on: e.date, id: e.id.uuidString)) }
                continue
            }
            let first = cal.component(.year, from: e.date)
            let years = max(0, cal.component(.year, from: interval.start) - first - 1)...max(0, cal.component(.year, from: interval.end) - first)
            for n in years {
                guard let date = cal.date(byAdding: .year, value: n, to: e.date), contains(date) else { continue }
                rows.append(row(e, on: date, id: "\(e.id.uuidString)-\(n)"))
            }
        }

        rows += planned.filter { contains($0.date) }.map(row)
        let (days, months, years) = milestones(since: start)
        rows += (days + months + years).filter { contains($0.date) }

        return rows.sorted { $0.date < $1.date }
    }

    private func row(_ event: UsEvent, on date: Date, id: String) -> Upcoming {
        Upcoming(id: id, title: event.title, icon: event.icon, date: date, source: .event(event.id))
    }

    private func row(_ plan: PlannedDate) -> Upcoming {
        Upcoming(id: plan.id.uuidString, title: DateIdea.idea(plan.ideaID)?.title ?? "Date",
                 icon: .init(symbol: "heart.text.square.fill", tint: .coral), date: plan.date, source: .date(plan.id))
    }

    /// Day counts, month anniversaries in the first year and yearly anniversaries for ten years, each in date order.
    private func milestones(since start: Date) -> (days: [Upcoming], months: [Upcoming], years: [Upcoming]) {
        let cal = Calendar.current
        let days = [100, 200, 300, 365, 500, 730, 1000, 1500, 2000].compactMap { n in
            cal.date(byAdding: .day, value: n - 1, to: start).map {
                Upcoming(id: "day-\(n)", title: "\(n) days together", icon: .init(symbol: "heart.fill", tint: .blush), date: $0, source: .milestone)
            }
        }
        let months = (1...11).compactMap { m in
            cal.date(byAdding: .month, value: m, to: start).map {
                Upcoming(id: "month-\(m)", title: "\(m) \(m == 1 ? "month" : "months") together", icon: .init(symbol: "sparkles", tint: .sun),
                         date: $0, source: .milestone)
            }
        }
        let years = (1...10).compactMap { y in
            cal.date(byAdding: .year, value: y, to: start).map {
                Upcoming(id: "year-\(y)", title: "\(y) \(y == 1 ? "year" : "years") together", icon: .init(symbol: "crown.fill", tint: .honey),
                         date: $0, source: .milestone)
            }
        }
        return (days, months, years)
    }

    // MARK: Dates

    func swipe(_ ideaID: Int, liked: Bool, by partner: String) {
        let wasMatch = isMatch(ideaID)
        swipes[partner, default: [:]][ideaID] = liked
        if !wasMatch && isMatch(ideaID) { wallet.earn(10) }
        save()
    }

    func isMatch(_ ideaID: Int) -> Bool {
        let liked = swipes.values.filter { $0[ideaID] == true }.count
        return liked >= 2
    }

    /// Both partners liked these, newest catalog first; planned ones excluded.
    var matches: [DateIdea] {
        var likes: [Int: Int] = [:]
        for partner in swipes.values {
            for (id, liked) in partner where liked { likes[id, default: 0] += 1 }
        }
        let plannedIDs = Set(planned.map(\.ideaID))
        return DateIdea.all.filter { likes[$0.id, default: 0] >= 2 && !plannedIDs.contains($0.id) }
    }

    /// The deck for one partner: ideas they haven't swiped yet, in-season first.
    func deck(for partner: String, filter: DateFilter) -> [DateIdea] {
        let seen = swipes[partner] ?? [:]
        let season = DateIdea.Season.current
        return DateIdea.all
            .filter { seen[$0.id] == nil && filter.allows($0) }
            // Same order for both partners so they meet the same cards; in-season ideas first.
            .sorted { ($0.inSeason(season) ? 0 : 1, $0.id) < ($1.inSeason(season) ? 0 : 1, $1.id) }
    }

    /// Matches first, then anything else that fits; skips ideas planned or done in the last 60 days.
    func randomIdea(filter: DateFilter, excluding: Set<Int> = []) -> DateIdea? {
        let recent = Set(planned.filter { $0.date > Date.now.addingTimeInterval(-60 * 86_400) }.map(\.ideaID))
        let pool = DateIdea.all.filter { filter.allows($0) && !recent.contains($0.id) && !excluding.contains($0.id) }
        let matched = pool.filter { isMatch($0.id) }
        if let pick = matched.randomElement() { return pick }
        // Out-of-season ideas stay possible, just three times less likely.
        let season = DateIdea.Season.current
        let weighted = pool.flatMap { Array(repeating: $0, count: $0.inSeason(season) ? 3 : 1) }
        return weighted.randomElement()
    }

    func upsertPlan(_ plan: PlannedDate) {
        if let i = planned.firstIndex(where: { $0.id == plan.id }) { planned[i] = plan } else { planned.append(plan) }
        save()
    }

    func deletePlan(_ id: UUID) {
        planned.removeAll { $0.id == id }
        save()
    }

    /// Rating a date marks it as done and earns the couple 30 coins once.
    func rate(_ id: UUID, hearts: Int) {
        guard let i = planned.firstIndex(where: { $0.id == id }) else { return }
        if planned[i].rating == nil { wallet.earn(30) }
        planned[i].rating = min(max(hearts, 1), 3)
        save()
    }

    /// Not yet rated first (soonest on top), then rated ones newest first.
    var plannedSorted: [PlannedDate] {
        let next = planned.filter { $0.rating == nil }.sorted { $0.date < $1.date }
        let past = planned.filter { $0.rating != nil }.sorted { $0.date > $1.date }
        return next + past
    }
}
