import Foundation
import Observation
import Wire

// MARK: - Store

/// Everything on the Us tab, as JSON in the app group shared with the widgets (docs/together-concept.md, section 6).
/// Once paired, the gifts mirror the pair's room through `GiftsModel` and the lists through `ListsModel`; the rest
/// stays on this phone.
@Observable
final class UsStore {
    private(set) var lists: [UsList] = []
    private(set) var wishes: [WishItem] = []
    /// Each giver's secret picks. Kept apart from `wishes` so that, once the couple syncs, they stay on the giver's
    /// phone.
    private(set) var plans: [GiftPlan] = []
    private(set) var loves: [String: Loves] = [:]
    /// Owners the pair's room says a surprise is coming for. The room never says which wish, and the plan behind it
    /// is on the giver's phone only.
    private(set) var surprises: Set<String> = []
    private(set) var events: [UsEvent] = []
    private(set) var planned: [PlannedDate] = []
    /// Per partner: idea id -> liked (true) or skipped (false).
    private(set) var swipes: [String: [Int: Bool]] = [:]
    /// Per partner: idea id -> when they last skipped it, so the deck deals skipped ideas again oldest first.
    private var passedAt: [String: [Int: Date]] = [:]

    /// Told of each thing done here that the server pays coins for. The app sends it there; the widgets pass none.
    @ObservationIgnored var onEarn: (EarnEvent) -> Void
    /// Called after each gift change made on this phone; the paired app sends it to the pair's room.
    @ObservationIgnored var onGiftChange: ((GiftChange) -> Void)?
    /// Called after each list change made on this phone while it follows the pair's room.
    @ObservationIgnored var onListChange: (() -> Void)?
    /// The lists as the pair's room last answered, under `pendingLists`; nil while the lists are this phone's own.
    private var roomLists: [UsList]?
    /// List changes made here, a widget's included, that the room has not answered yet, oldest first.
    private(set) var pendingLists: [PendingListChange] = []
    /// What the pair buys, for the grocery suggestions and the aisle a partner picked.
    private(set) var groceries = GroceryHistory()

    private let file: String

    private nonisolated struct Snapshot: Codable {
        var lists: [UsList]
        var wishes: [WishItem]
        var loves: [String: Loves]
        var events: [UsEvent]
        var planned: [PlannedDate]
        var swipes: [String: [Int: Bool]]
        /// Missing in files from builds before gift plans.
        var plans: [GiftPlan]?
        var surprises: Set<String>?
        /// Missing in files from builds before shared lists.
        var roomLists: [UsList]?
        var pendingLists: [PendingListChange]?
        /// Missing in files from builds before grocery tiles.
        var groceries: GroceryHistory?
        /// Missing in files from builds before skipped ideas came back.
        var passedAt: [String: [Int: Date]]?
    }

    init(file: String = "Us/us.json", onEarn: @escaping (EarnEvent) -> Void = { _ in }) {
        self.onEarn = onEarn
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
            plans = saved.plans ?? []
            surprises = saved.surprises ?? []
            roomLists = saved.roomLists
            pendingLists = saved.pendingLists ?? []
            groceries = saved.groceries ?? GroceryHistory()
            passedAt = saved.passedAt ?? [:]
            for i in wishes.indices {
                guard let giver = wishes[i].legacyGiver else { continue }
                wishes[i].legacyGiver = nil
                if wishes[i].gifted == nil && !plans.contains(where: { $0.wishID == wishes[i].id }) {
                    plans.append(GiftPlan(wishID: wishes[i].id, giver: giver))
                }
            }
        } else {
            // Starter lists are empty containers, not fake content.
            lists = [.watch, .groceries, .travel].map { UsList(kind: $0, title: $0.defaultTitle, icon: $0.icon) }
        }
    }

    private func save() {
        groceries.observe(lists)
        SharedFile.write(Snapshot(lists: lists, wishes: wishes, loves: loves, events: events, planned: planned, swipes: swipes,
                                  plans: plans, surprises: surprises, roomLists: roomLists, pendingLists: pendingLists,
                                  groceries: groceries, passedAt: passedAt),
                         to: file)
    }

    // MARK: Lists

    func list(_ id: UUID) -> UsList? { lists.first { $0.id == id } }

    /// Whether the lists follow the pair's room rather than being this phone's own.
    var followsRoomLists: Bool { roomLists != nil }

    @discardableResult
    func addList(kind: ListKind, title: String, icon: UsGlyph) -> UsList {
        let list = UsList(kind: kind, title: PendingListChange.line(title, max: 60) ?? kind.defaultTitle, icon: icon)
        perform(.createList(key: .make(), list: Self.key(list.id), kind: Wire.ListKind(kind),
                            title: list.title, icon: ListIcon(icon)), by: nil)
        return list
    }

    func renameList(_ id: UUID, title: String, icon: UsGlyph) {
        guard let title = PendingListChange.line(title, max: 60) else { return }
        perform(.renameList(key: .make(), list: Self.key(id), title: title, icon: ListIcon(icon)), by: nil)
    }

    func deleteList(_ id: UUID) {
        perform(.deleteList(key: .make(), list: Self.key(id)), by: nil)
    }

    /// A film or show added with its `media` is one the author wants to watch, so it starts with their want.
    func addItem(_ text: String, to listID: UUID, author: String, details: ListItemDetails = ListItemDetails(),
                 media: ItemMedia? = nil) {
        guard let text = PendingListChange.line(text, max: 300), list(listID) != nil else { return }
        let item = UUID()
        var details = details
        if let media { details.media = ListMedia(media) }
        perform(.addItem(key: .make(), list: Self.key(listID), item: Self.key(item), text: text, details: details),
                by: author)
        if media != nil { setWant(item, in: listID, wants: true, by: author) }
    }

    /// Adds a country, or a place in one, to a travel list. A place brings its country along, so it shows under it;
    /// a country already on the list isn't added again.
    func addTravel(country code: String, place: String? = nil, to listID: UUID, author: String) {
        guard let list = list(listID) else { return }
        if !list.items.contains(where: { $0.isCountry && $0.country == code }) {
            addItem(Country.name(code), to: listID, author: author, details: ListItemDetails(country: code))
        }
        if let place {
            addItem(place, to: listID, author: author, details: ListItemDetails(country: code, place: true))
        }
    }

    /// Marks a travel item been to, with the month and the photos from Moments; nil and empty clear them.
    func markBeen(_ itemID: UUID, in listID: UUID, month: TravelMonth?, moments: [UUID], by partner: String) {
        guard var details = list(listID)?.items.first(where: { $0.id == itemID })?.details else { return }
        details.visitedIn = month?.text
        details.moments = moments.isEmpty ? nil : moments.map(\.uuidString)
        setItem(itemID, in: listID, done: true, by: partner)
        editItem(itemID, in: listID, details: details)
    }

    /// Sets every detail, so one left nil is cleared.
    func editItem(_ itemID: UUID, in listID: UUID, details: ListItemDetails) {
        guard let item = list(listID)?.items.first(where: { $0.id == itemID }), item.details != details else { return }
        perform(.editItem(key: .make(), list: Self.key(listID), item: Self.key(itemID), text: item.text, details: details),
                by: nil)
    }

    /// Says `partner` wants the item, or no longer does.
    func setWant(_ itemID: UUID, in listID: UUID, wants: Bool, by partner: String) {
        guard let item = list(listID)?.items.first(where: { $0.id == itemID }),
              item.wants.contains(partner) != wants else { return }
        perform(.wantItem(key: .make(), list: Self.key(listID), item: Self.key(itemID), wants: wants), by: partner)
    }

    func toggleItem(_ itemID: UUID, in listID: UUID, by partner: String? = nil) {
        guard let item = list(listID)?.items.first(where: { $0.id == itemID }) else { return }
        setItem(itemID, in: listID, done: item.done == nil, by: partner)
    }

    /// Ticking a "we want to" item earns coins in the pair's room, within the daily cap; groceries earn nothing.
    func setItem(_ itemID: UUID, in listID: UUID, done: Bool, by partner: String? = nil) {
        guard let item = list(listID)?.items.first(where: { $0.id == itemID }), (item.done != nil) != done else {
            return
        }
        let (list, key) = (Self.key(listID), Self.key(itemID))
        perform(done ? .tickItem(key: .make(), list: list, item: key) : .untickItem(key: .make(), list: list, item: key),
                by: partner)
    }

    func deleteItem(_ itemID: UUID, in listID: UUID) {
        perform(.deleteItem(key: .make(), list: Self.key(listID), item: Self.key(itemID)), by: nil)
    }

    /// Groceries: drop everything already bought.
    func clearDone(in listID: UUID) {
        for item in list(listID)?.items ?? [] where item.done != nil { deleteItem(item.id, in: listID) }
    }

    private func perform(_ change: ListCommand, by partner: String?) {
        let pending = PendingListChange(change: change, by: partner, at: .now)
        lists = pending.apply(to: lists)
        if roomLists != nil {
            pendingLists.append(pending)
            onListChange?()
        }
        save()
    }

    /// Takes the room's lists as the truth, with the changes it has not answered yet on top. The first time, this
    /// phone's own lists join the room's: each is queued for upload unless the room has it, or it is an empty
    /// starter list of a kind the room already has.
    func mirrorLists(_ room: [UsList], me: String) {
        if roomLists == nil {
            pendingLists = PendingListChange.upload(lists, missingFrom: room, by: me) + pendingLists
        }
        roomLists = room
        lists = pendingLists.reduce(room) { $1.apply(to: $0) }
        save()
    }

    /// The room answered the change with `key`, or refused it for good.
    func listChangeDone(_ key: IdempotencyKey, room: [UsList]?) {
        pendingLists.removeAll { $0.change.key == key }
        if let room { roomLists = room }
        lists = pendingLists.reduce(roomLists ?? lists) { $1.apply(to: $0) }
        save()
    }

    /// The lists become this phone's own again, as they stand.
    func leaveRoomLists() {
        guard roomLists != nil else { return }
        roomLists = nil
        pendingLists = []
        save()
    }

    nonisolated static func key(_ id: UUID) -> IdempotencyKey { IdempotencyKey(id.uuidString) }

    // MARK: Wishlists

    /// Still wanted: most wanted first, then newest.
    func wishes(of owner: String) -> [WishItem] {
        wishes.filter { $0.owner == owner && $0.gifted == nil }
            .sorted { ($0.mostWanted ? 0 : 1, $1.added) < ($1.mostWanted ? 0 : 1, $0.added) }
    }

    func gifted(to owner: String) -> [WishItem] {
        wishes.filter { $0.owner == owner && $0.gifted != nil }.sorted { $0.gifted! > $1.gifted! }
    }

    func upsertWish(_ wish: WishItem) {
        if let i = wishes.firstIndex(where: { $0.id == wish.id }) { wishes[i] = wish } else { wishes.append(wish) }
        save()
        onGiftChange?(.save(wish))
    }

    func deleteWish(_ id: UUID) {
        wishes.removeAll { $0.id == id }
        plans.removeAll { $0.wishID == id }
        save()
        onGiftChange?(.delete(id))
    }

    /// The viewer's own plan for this wish. Nobody else's plan is ever returned, so the owner gets nil for their own wishes.
    func plan(for wishID: UUID, viewer: String) -> GiftPlan? {
        plans.first { $0.wishID == wishID && $0.giver == viewer }
    }

    /// The owner may learn that a surprise is coming, never for which wish.
    func surpriseComing(for owner: String) -> Bool {
        let open = Set(wishes(of: owner).map(\.id))
        return surprises.contains(owner) || plans.contains { open.contains($0.wishID) && $0.giver != owner }
    }

    /// The giver secretly promises to gift it. One plan per wish; the owner can't plan their own.
    func pick(_ id: UUID, by giver: String) {
        guard let wish = wishes.first(where: { $0.id == id }), wish.owner != giver, wish.gifted == nil,
              !plans.contains(where: { $0.wishID == id }) else { return }
        plans.append(GiftPlan(wishID: id, giver: giver))
        save()
        onGiftChange?(.plan(id, .planning))
    }

    func setStage(_ stage: GiftPlan.Stage, of id: UUID, by giver: String) {
        guard let i = plans.firstIndex(where: { $0.wishID == id && $0.giver == giver }) else { return }
        plans[i].stage = stage
        save()
        onGiftChange?(.plan(id, stage))
    }

    func release(_ id: UUID, by giver: String) {
        plans.removeAll { $0.wishID == id && $0.giver == giver }
        save()
        onGiftChange?(.plan(id, nil))
    }

    /// Only the owner says it arrived: it moves to "Gifted", the giver's plan closes and the couple earns 20 coins once.
    func markReceived(_ id: UUID, by owner: String) {
        guard let i = wishes.firstIndex(where: { $0.id == id }), wishes[i].owner == owner, wishes[i].gifted == nil
        else { return }
        wishes[i].gifted = .now
        wishes[i].giftedBy = plans.first { $0.wishID == id }?.giver
        plans.removeAll { $0.wishID == id }
        if !wishes[i].rewarded {
            wishes[i].rewarded = true
            onEarn(.wishReceived(wish: id.uuidString))
        }
        save()
        onGiftChange?(.received(id, true))
    }

    /// Puts a wish marked by mistake back on the list. The coins stay paid.
    func unmarkReceived(_ id: UUID, by owner: String) {
        guard let i = wishes.firstIndex(where: { $0.id == id }), wishes[i].owner == owner else { return }
        wishes[i].gifted = nil
        wishes[i].giftedBy = nil
        save()
        onGiftChange?(.received(id, false))
    }

    func loves(of partner: String) -> Loves { loves[partner] ?? Loves() }

    func setLoves(_ value: Loves, for partner: String) {
        loves[partner] = value
        save()
        onGiftChange?(.loves(value, of: partner))
    }

    /// Takes the pair's room as the truth for gifts. `plans` are only the viewer's own; `surprise` names the owner a
    /// surprise is coming for, if any. Whether a wish's coins were paid is the phone's own and stays.
    func mirrorGifts(wishes remote: [WishItem], plans: [GiftPlan], loves: [String: Loves], surprise: String?) {
        let paid = Set(wishes.filter(\.rewarded).map(\.id))
        wishes = remote.map { wish in
            var wish = wish
            wish.rewarded = paid.contains(wish.id) || wish.gifted != nil
            return wish
        }
        self.plans = plans
        self.loves = loves
        surprises = surprise.map { [$0] } ?? []
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

    // MARK: Dates

    func swipe(_ ideaID: Int, liked: Bool, by partner: String) {
        let wasMatch = isMatch(ideaID)
        swipes[partner, default: [:]][ideaID] = liked
        passedAt[partner, default: [:]][ideaID] = liked ? nil : .now
        if !wasMatch && isMatch(ideaID) { onEarn(.dateMatched(idea: String(ideaID))) }
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

    /// The deck for one partner: ideas they haven't swiped yet, in-season first, then the ones they skipped, skipped
    /// longest ago first. So the deck never runs out while something is left to like; liked ideas never come back.
    func deck(for partner: String, filter: DateFilter) -> [DateIdea] {
        let seen = swipes[partner] ?? [:]
        let passed = passedAt[partner] ?? [:]
        let season = DateIdea.Season.current
        let fitting = DateIdea.all.filter { seen[$0.id] != true && filter.allows($0) }
        // Same order for both partners so they meet the same cards; in-season ideas first.
        let new = fitting.filter { seen[$0.id] == nil }
            .sorted { ($0.inSeason(season) ? 0 : 1, $0.id) < ($1.inSeason(season) ? 0 : 1, $1.id) }
        // Skips from before `passedAt` have no date and come first.
        let again = fitting.filter { seen[$0.id] == false }
            .sorted { (passed[$0.id] ?? .distantPast, $0.id) < (passed[$1.id] ?? .distantPast, $1.id) }
        return new + again
    }

    /// Whether this idea is in the partner's deck again after they skipped it.
    func isSecondLook(_ ideaID: Int, for partner: String) -> Bool { swipes[partner]?[ideaID] == false }

    /// Ideas the partner hasn't swiped at all.
    func unseenCount(for partner: String, filter: DateFilter) -> Int {
        let seen = swipes[partner] ?? [:]
        return DateIdea.all.count { seen[$0.id] == nil && filter.allows($0) }
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

    /// Rating a date marks it as done and earns the couple coins once.
    func rate(_ id: UUID, hearts: Int, momentID: UUID? = nil) {
        guard let i = planned.firstIndex(where: { $0.id == id }) else { return }
        if planned[i].rating == nil { onEarn(.dateRated(plan: id.uuidString)) }
        planned[i].rating = min(max(hearts, 1), 3)
        if let momentID { planned[i].momentID = momentID }
        save()
    }

    /// Not done yet, soonest first; the ones already past wait on top for "How was it?".
    var comingUp: [PlannedDate] { planned.filter { $0.rating == nil }.sorted { $0.date < $1.date } }

    /// Rated, newest first.
    var done: [PlannedDate] { planned.filter { $0.rating != nil }.sorted { $0.date > $1.date } }

    /// Not yet rated first (soonest on top), then rated ones newest first.
    var plannedSorted: [PlannedDate] { comingUp + done }
}
