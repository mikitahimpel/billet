import FeatureShop
import Foundation
import Observation
import OurioShared
import ShopInterface
import Transport
import Wire

/// The Shop's store around `ShopMachine` (FeatureShop), with the wallet file, the cat and the day's prices.
/// Only the server changes coins: every buy, treat, gift, bonus and earn is a request to it, and the balance
/// shown is its last answer less the buys not sent yet.
@Observable
final class ShopModel: CoinsBalanceProviding, CoinEarning, TreatBuying {
    nonisolated static let treatPrice = ShopMachine.treatPrice
    /// Tries of one request while the network is down, the first included.
    nonisolated static let attempts = 3

    typealias GiftOutcome = ShopInterface.GiftOutcome

    @ObservationIgnored let wallet: WalletStore
    @ObservationIgnored private let couple: CoupleStore
    @ObservationIgnored private let care: CatCare
    /// Nil until this phone follows a pair on the server, and with it nothing can be bought or earned.
    @ObservationIgnored private var sync: ShopSync?
    @ObservationIgnored var undoWindow: Duration = .seconds(Purchase.undoWindow)
    @ObservationIgnored var retryDelay: Duration = .seconds(2)
    @ObservationIgnored private var store: ShopStore!
    /// Rooms the wallet file has let go of, so leaving one can wait for it.
    private var left = 0

    init(wallet: WalletStore, couple: CoupleStore, care: CatCare) {
        self.wallet = wallet
        self.couple = couple
        self.care = care
        store = .shop(
            ShopServices(
                client: { [unowned self] in self.sync },
                undoWindow: { [unowned self] in self.undoWindow },
                retryDelay: { [unowned self] in self.retryDelay },
                attempts: Self.attempts,
                // Outputs finish in any order: an answer that lands after the pair ended stays out of the wallet.
                mirror: { [weak self] in
                    guard self?.isSynced == true else { return }
                    wallet.mirror(coins: $0.balance, owned: $0.owned, wishlist: $0.wishlist)
                },
                mirrorBalance: { [weak self] in
                    guard self?.isSynced == true else { return }
                    wallet.mirror(balance: $0)
                },
                mirrorWish: { itemID, wished in
                    wallet.update {
                        if wished {
                            _ = $0.wishlist.insert(itemID)
                        } else {
                            _ = $0.wishlist.remove(itemID)
                        }
                    }
                },
                markGifted: { added in wallet.update { $0.gifted.formUnion(added) } },
                leaveWallet: { [weak self] in
                    wallet.leaveSync()
                    self?.left += 1
                },
                catFed: { care.fed() },
                catNoticed: { care.notice() }))
    }

    var state: ShopMachine.State { store.state }

    private var open: ShopMachine.PairShop? {
        if case .open(let shop) = store.state { shop } else { nil }
    }

    /// Buys shown on this phone that the server hasn't charged yet.
    var pending: [Purchase] { open?.pending ?? [] }
    /// The latest buy: the purchase moment plays for it and offers Undo for a few seconds.
    var lastPurchase: Purchase? {
        if case .placed(let purchase) = open?.moment { purchase } else { nil }
    }
    /// The latest buy the server didn't take; the purchase moment says so.
    var refused: Purchase? {
        switch store.state {
        case .offline(let refused, _): refused
        case .open(let shop): if case .refused(let purchase) = shop.moment { purchase } else { nil }
        }
    }
    /// The pair's local day it last opened the gift on, as the server said.
    var giftDay: String? { open?.giftDay }
    var bonuses: Set<String> { open?.bonuses ?? [] }
    /// The inks on sale, the free one first: the server's catalog once it has answered.
    var inks: [PaletteInk] {
        let listed = open?.inks.compactMap(PaletteInk.init) ?? []
        return listed.isEmpty ? PaletteInk.bundled : listed
    }
    /// Newest first.
    var history: [CoinEntry] { open?.history ?? [] }
    /// The Coins sheet, open when set: from the header's coins, or for a buy the balance doesn't cover.
    var coinsAsk: CoinsAsk? {
        get {
            switch store.state {
            case .offline(_, let ask): ask
            case .open(let shop): shop.ask
            }
        }
        set {
            if let ask = newValue {
                store.send(.coinsAsked(ask))
            } else {
                store.send(.coinsSheetClosed)
            }
        }
    }

    var isSynced: Bool { open != nil }
    /// Offline, the wallet file's last mirror of the room.
    var coins: Int { open?.coins ?? max(0, wallet.wallet.coins) }
    var owned: Set<String> { open?.owned ?? wallet.wallet.owned }
    var wishlist: Set<String> { open?.wishlist ?? wallet.wallet.wishlist }
    var gifted: Set<String> { wallet.wallet.gifted.union(open?.giftedPending ?? []) }

    /// The same on both partners' phones and on the server.
    var offers: ShopOffers {
        ShopOffers(pairSeed: couple.couple.pair?.pairID ?? couple.couple.partners.sorted().joined(separator: "+"))
    }

    /// Today's price: the deal price when the item is one of today's deals, as the server charges it.
    func price(of item: ShopItem, on date: Date = .now) -> Int {
        let offers = offers
        let key = "\(offers.pairSeed)|\(offers.dayKey(date))"
        let deals: [DailyDeal]
        if let cached = dealsByDay, cached.key == key {
            deals = cached.deals
        } else {
            deals = offers.deals(on: date)
            dealsByDay = (key, deals)
        }
        return deals.first { $0.itemID == item.id }?.price(of: item) ?? item.price
    }

    /// The day's deals for the pair, drawn once: every price on the Shop asks for them, several times a card.
    @ObservationIgnored private var dealsByDay: (key: String, deals: [DailyDeal])?

    // MARK: Buying

    /// At the set price: the featured set or a bundle.
    @discardableResult
    func buy(_ set: some PieceSet) -> Bool {
        guard let quote = ShopOffers.price(of: set, owned: owned) else { return false }
        return place(ShopOrder(offer: .set(PieceSetId(set.id)), itemIDs: set.itemIDs, cost: quote.price, title: set.name))
    }

    /// Gifts arrive wrapped and the partner unwraps them.
    @discardableResult
    func buy(_ item: ShopItem, asGift: Bool = false) -> Bool {
        place(
            ShopOrder(
                offer: .item(RoomItemId(item.id)), itemIDs: [item.id], cost: price(of: item), title: item.name,
                asGift: asGift))
    }

    @discardableResult
    func buy(_ ink: PaletteInk) -> Bool {
        guard !ink.isOwned(owned) else { return false }
        return place(
            ShopOrder(offer: .ink(ink.wireID), itemIDs: [ink.id], cost: ink.price, title: "\(ink.name) ink", kind: .ink))
    }

    /// Takes a buy back within its Undo window, before the server hears of it.
    @discardableResult
    func undo(_ purchase: Purchase, at now: Date = .now) -> Bool {
        guard purchase.canUndo(at: now) else { return false }
        store.send(.undoTapped(purchase.id))
        return !pending.contains { $0.id == purchase.id }
    }

    /// Opens the Coins sheet: just the coins, or for a buy that needs `missing` more, which it can finish after.
    func askForCoins(missing: Int = 0, then retry: CoinsAsk.Retry? = nil) {
        store.send(.coinsAsked(CoinsAsk(missing: max(0, missing), retry: retry)))
    }

    /// Buys again what the balance didn't cover, once it does. False while it still doesn't, or if it's owned now.
    @discardableResult
    func finish(_ retry: CoinsAsk.Retry) -> Bool {
        retry.kind == .treat ? treat() : place(retry)
    }

    /// A treat: Mochi eats it at once and the server is asked for it at once, as it has no Undo.
    func treat() -> Bool {
        let before = Set(pending.map(\.id))
        store.send(.treatTapped(id: UUID(), at: .now))
        return pending.contains { !before.contains($0.id) }
    }

    /// True when the buy was placed; false when the Coins sheet opened for it, or it was refused.
    private func place(_ order: ShopOrder) -> Bool {
        // Offline the machine has no owned set; a piece owned already is nothing to buy, not a refusal.
        if open == nil, order.itemIDs.allSatisfy(owned.contains) { return false }
        let before = Set(pending.map(\.id))
        store.send(.buyTapped(order, id: UUID(), at: .now))
        return pending.contains { !before.contains($0.id) }
    }

    func toggleWish(_ item: ShopItem) {
        store.send(.wishToggled(itemID: item.id, wished: !wishlist.contains(item.id)))
    }

    // MARK: Gift and collections

    func canClaimGift(on date: Date = .now) -> Bool { isSynced && giftDay != Self.localDay(date) }

    /// Opens the day's gift on the server. `taken` when it was open already (the server's 409 GiftTaken, or a refusal
    /// after which the room shows it open); nil when it couldn't be asked.
    func openGift(at date: Date = .now) async -> GiftOutcome? {
        guard canClaimGift(on: date) else { return nil }
        store.send(.giftTapped(day: Self.localDay(date)))
        await until {
            switch self.open?.gift {
            case .opening, .checking: false
            case .idle, .opened, .taken, .failed, nil: true
            }
        }
        defer { store.send(.giftShown) }
        switch open?.gift {
        case .opened(let reward): return .opened(reward)
        case .taken: return .taken
        case .idle, .opening, .checking, .failed, nil: return nil
        }
    }

    /// The bonus waits until every piece is owned, and is collected once.
    func canClaimBonus(_ collection: ShopCollection) -> Bool {
        isSynced && collection.isComplete(owned) && !bonuses.contains(collection.id)
    }

    /// Collects the bonus on the server. A refusal reads the room again; one already paid (409 BonusTaken, the
    /// partner was quicker) shows as collected.
    func claimBonus(_ collection: ShopCollection) async -> Bool {
        guard canClaimBonus(collection) else { return false }
        store.send(.bonusTapped(collection: collection.id, itemIDs: collection.itemIDs))
        await until {
            switch self.open?.bonus {
            case .claiming, .refusing: false
            case .idle, .claimed, .refused, nil: true
            }
        }
        defer { store.send(.bonusShown) }
        if case .claimed = open?.bonus { return true }
        return false
    }

    // MARK: Earning

    /// Asks the server to pay for something the couple did. The event names what it was, so a retry, or the same
    /// thing again, is paid once; the balance shown is the server's answer.
    func earn(_ event: EarnEvent) {
        store.send(.earnAsked(event))
    }

    /// Reads the latest wallet entries, paging from the oldest as the server lists them.
    func loadHistory(limit: Int = 10) async {
        guard isSynced else { return }
        store.send(.historyAsked(limit: limit))
        await until { self.open?.historyLoad == .idle }
    }

    // MARK: Server

    /// Follows the pair's room on the server, or, with nil, forgets it.
    func connect(_ sync: ShopSync?) async {
        self.sync = sync
        guard sync != nil else {
            guard isSynced else {
                // No room followed this launch, but the file may still hold the last pair's.
                if wallet.wallet.isSynced { wallet.leaveSync() }
                return
            }
            let leaving = left
            store.send(.disconnected)
            return await until { self.left != leaving }
        }
        let last = wallet.wallet
        store.send(.connected(last: ShopMachine.Mirror(balance: last.coins, owned: last.owned, wishlist: last.wishlist)))
        await untilRead()
    }

    func refresh() async {
        guard isSynced else { return }
        store.send(.refreshAsked)
        await untilRead()
    }

    /// The socket's push after either partner's change; ignored unless this phone follows a room.
    func received(_ shop: ShopResponse) {
        store.send(.pushed(shop))
    }

    private func untilRead() async {
        await until { self.open.map { $0.fetch == .idle && $0.inkLoad == .idle } ?? true }
    }

    private func until(_ done: @escaping () -> Bool) async {
        await store.until(done)
    }

    nonisolated static func utcOffset(at date: Date) -> Int { ShopMachine.utcOffset(at: date) }

    /// `YYYY-MM-DD` on this phone's calendar, the day the server counts the gift on.
    nonisolated static func localDay(_ date: Date, calendar: Calendar = .current) -> String {
        ShopMachine.localDay(date, calendar: calendar)
    }
}
