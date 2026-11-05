import Foundation
import Observation
import Transport
import Wire

/// The Shop: the pair's coins, pieces, inks and wishlist as the room on the server keeps them, the day's offers, the
/// free gift and the collection bonuses.
///
/// Only the server changes coins. Every buy, treat, gift, bonus and earn is a request to it, and the balance shown is
/// the one in its last answer, less the buys it hasn't been sent yet. A buy shows at once and waits out its Undo window
/// on the phone; only then is it ordered, under one id for every retry. One the server refuses, or that never reaches
/// it, is taken back and the room read again.
@Observable
final class ShopModel {
    nonisolated static let treatPrice = 10
    /// Tries of one request while the network is down, the first included.
    nonisolated static let attempts = 3

    @ObservationIgnored let wallet: WalletStore
    @ObservationIgnored private let couple: CoupleStore
    @ObservationIgnored private let care: CatCare
    /// Nil until this phone follows a pair on the server, and with it nothing can be bought or earned.
    @ObservationIgnored private var sync: ShopSync?
    @ObservationIgnored var undoWindow: Duration = .seconds(Purchase.undoWindow)
    @ObservationIgnored var retryDelay: Duration = .seconds(2)

    init(wallet: WalletStore, couple: CoupleStore, care: CatCare) {
        self.wallet = wallet
        self.couple = couple
        self.care = care
    }

    /// Buys shown on this phone that the server hasn't charged yet.
    private(set) var pending: [Purchase] = []
    /// The latest buy: the purchase moment plays for it and offers Undo for a few seconds.
    private(set) var lastPurchase: Purchase?
    /// The latest buy the server didn't take; the purchase moment says so.
    private(set) var refused: Purchase?
    /// The pair's local day it last opened the gift on, as the server said.
    private(set) var giftDay: String?
    /// The collections whose bonus the pair has collected.
    private(set) var bonuses: Set<String> = []
    /// The inks on sale, the free one first: the server's catalog once it has answered.
    private(set) var inks = PaletteInk.bundled
    /// The pair's latest wallet entries, newest first.
    private(set) var history: [CoinEntry] = []
    /// The Coins sheet, open when set: from the header's coins, or for a buy the balance doesn't cover.
    var coinsAsk: CoinsAsk?

    var isSynced: Bool { sync != nil }
    var coins: Int { max(0, wallet.wallet.coins - pending.reduce(0) { $0 + $1.cost }) }
    var owned: Set<String> { wallet.wallet.owned.union(pending.flatMap(\.added)) }
    var wishlist: Set<String> { wallet.wallet.wishlist.subtracting(pending.flatMap(\.added)) }
    var gifted: Set<String> { wallet.wallet.gifted.union(pending.filter(\.asGift).flatMap(\.added)) }

    /// The Shop's daily and weekly rotations, the same on both partners' phones and on the server.
    var offers: ShopOffers {
        ShopOffers(pairSeed: couple.couple.pair?.pairID ?? couple.couple.partners.sorted().joined(separator: "+"))
    }

    /// Today's price: the deal price when the item is one of today's deals, as the server charges it.
    func price(of item: ShopItem, on date: Date = .now) -> Int {
        offers.deal(for: item.id, on: date)?.price(of: item) ?? item.price
    }

    // MARK: Buying

    /// Buys a set's missing pieces at the set price: the featured set or a bundle.
    @discardableResult
    func buy(_ set: some PieceSet) -> Bool {
        guard let quote = ShopOffers.price(of: set, owned: owned) else { return false }
        return place(.set(PieceSetId(set.id)), itemIDs: set.itemIDs, cost: quote.price, title: set.name)
    }

    /// Gifts arrive wrapped and the partner unwraps them.
    @discardableResult
    func buy(_ item: ShopItem, asGift: Bool = false) -> Bool {
        place(.item(RoomItemId(item.id)), itemIDs: [item.id], cost: price(of: item), title: item.name, asGift: asGift)
    }

    @discardableResult
    func buy(_ ink: PaletteInk) -> Bool {
        guard !ink.isOwned(owned) else { return false }
        return place(.ink(ink.wireID), itemIDs: [ink.id], cost: ink.price, title: "\(ink.name) ink", kind: .ink)
    }

    /// Takes a buy back within its Undo window, before the server hears of it.
    @discardableResult
    func undo(_ purchase: Purchase, at now: Date = .now) -> Bool {
        guard lastPurchase?.id == purchase.id, purchase.canUndo(at: now), isPending(purchase) else { return false }
        pending.removeAll { $0.id == purchase.id }
        lastPurchase = nil
        return true
    }

    /// Opens the Coins sheet: just the coins, or for a buy that needs `missing` more, which it can finish after.
    func askForCoins(missing: Int = 0, then retry: CoinsAsk.Retry? = nil) {
        coinsAsk = CoinsAsk(missing: max(0, missing), retry: retry)
    }

    /// Buys again what the balance didn't cover, once it does. False while it still doesn't, or if it's owned now.
    @discardableResult
    func finish(_ retry: CoinsAsk.Retry) -> Bool {
        if retry.kind == .treat { return treat() }
        return place(
            retry.offer, itemIDs: retry.itemIDs, cost: retry.cost, title: retry.title, kind: retry.kind,
            asGift: retry.asGift)
    }

    /// A treat: Mochi eats it at once and the server is asked for it at once, as it has no Undo.
    func treat() -> Bool {
        guard sync != nil else { return false }
        guard coins >= Self.treatPrice else {
            askForCoins(
                missing: Self.treatPrice - coins,
                then: CoinsAsk.Retry(offer: .treat, itemIDs: [], cost: Self.treatPrice, title: "A treat", kind: .treat))
            return false
        }
        let purchase = Purchase(
            offer: .treat, itemIDs: [], added: [], cost: Self.treatPrice, date: .now, title: "Treat", kind: .treat)
        pending.append(purchase)
        care.fed()
        Task { await order(purchase) }
        return true
    }

    private func place(
        _ offer: ShopOffer, itemIDs: [String], cost: Int, title: String, kind: Purchase.Kind = .item,
        asGift: Bool = false
    ) -> Bool {
        let added = itemIDs.filter { !owned.contains($0) }
        guard sync != nil, !added.isEmpty else { return false }
        guard coins >= cost else {
            askForCoins(
                missing: cost - coins,
                then: CoinsAsk.Retry(
                    offer: offer, itemIDs: itemIDs, cost: cost, title: title, kind: kind, asGift: asGift))
            return false
        }
        let purchase = Purchase(
            offer: offer, itemIDs: itemIDs, added: added, cost: cost, date: .now, title: title, kind: kind,
            asGift: asGift)
        pending.append(purchase)
        lastPurchase = purchase
        refused = nil
        care.notice()
        Task { await settle(purchase) }
        return true
    }

    private func isPending(_ purchase: Purchase) -> Bool { pending.contains { $0.id == purchase.id } }

    /// Orders `purchase` once its Undo window is over, if it still stands.
    private func settle(_ purchase: Purchase) async {
        try? await Task.sleep(for: undoWindow)
        guard isPending(purchase) else { return }
        await order(purchase)
    }

    private func order(_ purchase: Purchase) async {
        guard let sync else { return pending.removeAll { $0.id == purchase.id } }
        let request = OrderRequest(
            id: purchase.key, offer: purchase.offer, utcOffsetSeconds: Self.utcOffset(at: purchase.date))
        do {
            let response = try await retrying { () async throws(TransportError) in try await sync.order(request) }
            pending.removeAll { $0.id == purchase.id }
            if purchase.asGift { wallet.update { $0.gifted.formUnion(purchase.added) } }
            apply(response.shop)
        } catch {
            pending.removeAll { $0.id == purchase.id }
            if lastPurchase?.id == purchase.id { lastPurchase = nil }
            if case .api(.notEnoughCoins(let needed, let have)) = error as? TransportError {
                // The partner spent the coins first: offer to top up and finish, rather than only refusing.
                askForCoins(missing: needed - have, then: CoinsAsk.Retry(purchase))
            } else if purchase.kind != .treat {
                refused = purchase
            }
            await refresh()
        }
    }

    func toggleWish(_ item: ShopItem) {
        let wished = !wishlist.contains(item.id)
        wallet.update {
            if wished {
                _ = $0.wishlist.insert(item.id)
            } else {
                _ = $0.wishlist.remove(item.id)
            }
        }
        guard let sync else { return }
        let request = WishRequest(item: RoomItemId(item.id), wished: wished)
        Task {
            if let shop = try? await sync.wish(request) { apply(shop) } else { await refresh() }
        }
    }

    // MARK: Gift and collections

    enum GiftOutcome: Hashable {
        case opened(GiftReward)
        /// The day's gift was open already, by the partner or an earlier try.
        case taken
    }

    func canClaimGift(on date: Date = .now) -> Bool { sync != nil && giftDay != Self.localDay(date) }

    /// Opens the day's gift on the server. `taken` when it was open already (the server's 409 GiftTaken, or a refusal
    /// after which the room shows it open); nil when it couldn't be asked.
    func openGift(at date: Date = .now) async -> GiftOutcome? {
        guard let sync, canClaimGift(on: date) else { return nil }
        let request = OpenGiftRequest(utcOffsetSeconds: Self.utcOffset(at: date))
        do {
            let response = try await retrying { () async throws(TransportError) in try await sync.openGift(request) }
            apply(response.shop)
            if giftDay == nil { giftDay = Self.localDay(date) }
            return .opened(GiftReward(response.reward))
        } catch {
            if case .api(.giftTaken(let day)) = error { giftDay = day }
            await refresh()
            return giftDay == Self.localDay(date) ? .taken : nil
        }
    }

    /// The bonus waits until every piece is owned, and is collected once.
    func canClaimBonus(_ collection: ShopCollection) -> Bool {
        sync != nil && collection.isComplete(owned) && !bonuses.contains(collection.id)
    }

    /// Collects the bonus on the server. A refusal reads the room again; one already paid (409 BonusTaken, the
    /// partner was quicker) shows as collected.
    func claimBonus(_ collection: ShopCollection) async -> Bool {
        guard let sync, canClaimBonus(collection) else { return false }
        let request = ClaimBonusRequest(collection: collection.id)
        do {
            let response = try await retrying { () async throws(TransportError) in try await sync.claimBonus(request) }
            apply(response.shop)
            return true
        } catch {
            if case .api(.bonusTaken) = error { bonuses.insert(collection.id) }
            await refresh()
            return false
        }
    }

    // MARK: Earning

    /// Asks the server to pay for something the couple did. The event names what it was, so a retry, or the same
    /// thing again, is paid once; the balance shown is the server's answer.
    func earn(_ event: EarnEvent, at date: Date = .now) {
        guard let sync else { return }
        let request = EarnRequest(event: event, utcOffsetSeconds: Self.utcOffset(at: date))
        Task {
            guard let response = try? await retrying({ () async throws(TransportError) in try await sync.earn(request) })
            else { return }
            wallet.mirror(balance: response.balance)
        }
    }

    /// Reads the latest wallet entries, paging from the oldest as the server lists them.
    func loadHistory(limit: Int = 10) async {
        guard let sync else { return }
        var after: String?
        var latest: [CoinEntry] = []
        while true {
            guard let page = try? await sync.coins(after) else { return }
            latest = Array((latest + page.entries).suffix(limit))
            guard page.entries.count >= Self.coinsPage, let last = page.entries.last else {
                wallet.mirror(balance: page.balance)
                break
            }
            after = last.id
        }
        history = latest.reversed()
    }

    /// The server's page of wallet entries.
    private static let coinsPage = 100

    // MARK: Server

    /// Follows the pair's room on the server, or, with nil, forgets it.
    func connect(_ sync: ShopSync?) async {
        self.sync = sync
        guard sync != nil else {
            pending = []
            lastPurchase = nil
            giftDay = nil
            bonuses = []
            history = []
            return wallet.leaveSync()
        }
        await refresh()
    }

    /// Reads the pair's room again.
    func refresh() async {
        guard let sync else { return }
        if let catalog = try? await sync.inks() {
            let known = catalog.inks.compactMap(PaletteInk.init)
            if !known.isEmpty { inks = known }
        }
        if let shop = try? await sync.fetch() { apply(shop) }
    }

    private func apply(_ shop: ShopResponse) {
        wallet.mirror(
            coins: shop.balance,
            owned: Set(shop.items.map(\.rawValue)).union(shop.inks.map(\.rawValue)),
            wishlist: Set(shop.wishlist.map(\.rawValue)))
        giftDay = shop.giftDay
        bonuses = Set(shop.bonuses)
    }

    /// Asks again while the network is down, with the same request.
    private func retrying<T>(
        _ call: () async throws(TransportError) -> T
    ) async throws(TransportError) -> T {
        var attempt = 1
        while true {
            do {
                return try await call()
            } catch {
                guard case .network = error, attempt < Self.attempts else { throw error }
                attempt += 1
                try? await Task.sleep(for: retryDelay)
            }
        }
    }

    nonisolated static func utcOffset(at date: Date) -> Int { TimeZone.current.secondsFromGMT(for: date) }

    /// `YYYY-MM-DD` on this phone's calendar, the day the server counts the gift on.
    nonisolated static func localDay(_ date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }
}

extension GiftReward {
    init(_ reward: Wire.GiftReward) {
        switch reward {
        case .coins(let coins): self = .coins(coins)
        case .item(let item): self = .item(item.rawValue)
        }
    }
}
