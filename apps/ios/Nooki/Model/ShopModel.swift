import Foundation
import Observation
import Transport
import Wire

/// The Shop: the shared wallet, the day's offers, the free gift, collections and the wishlist.
///
/// While the pair is on a server the room there is the truth: it prices and records every buy, treat and wish, and
/// the wallet file mirrors it. A buy shows at once and the server's answer then replaces the wallet. Nothing on the
/// phone earns coins meanwhile, so the gift, collection bonuses and deals wait until the server offers them.
@Observable
final class ShopModel {
    nonisolated static let treatPrice = 10

    @ObservationIgnored let wallet: WalletStore
    @ObservationIgnored private let couple: CoupleStore
    @ObservationIgnored private let care: CatCare
    /// Nil while this phone has no partner on a server.
    @ObservationIgnored private var sync: ShopSync?

    init(wallet: WalletStore, couple: CoupleStore, care: CatCare) {
        self.wallet = wallet
        self.couple = couple
        self.care = care
    }

    var isSynced: Bool { wallet.wallet.isSynced }
    var coins: Int { wallet.wallet.coins }
    var owned: Set<String> { wallet.wallet.owned }
    var wishlist: Set<String> { wallet.wallet.wishlist }
    var gifted: Set<String> { wallet.wallet.gifted }

    /// The Shop's daily and weekly rotations, the same on both partners' phones.
    var offers: ShopOffers {
        ShopOffers(pairSeed: couple.couple.pair?.pairID ?? couple.couple.partners.sorted().joined(separator: "+"))
    }

    /// Today's price: the deal price when the item is one of today's deals. The server sells at the catalog price.
    func price(of item: ShopItem, on date: Date = .now) -> Int {
        if isSynced { return item.price }
        return offers.deal(for: item.id, on: date)?.price(of: item) ?? item.price
    }

    // MARK: Gift and collections

    private static let giftFile = "Shop/gift.json"
    private(set) var giftLog = SharedFile.read(GiftLog.self, from: giftFile) ?? GiftLog()

    func canClaimGift(on date: Date = .now) -> Bool { !isSynced && giftLog.canClaim(on: date) }

    /// Opens the day's free gift: coins into the wallet, or an item into the room's closet. Nil if it's already open.
    func claimGift(on date: Date = .now) -> GiftReward? {
        guard canClaimGift(on: date) else { return nil }
        let reward = offers.gift(on: date, owned: owned)
        wallet.update {
            switch reward {
            case .coins(let amount): $0.coins += amount
            case .item(let id): $0.owned.insert(id)
            }
        }
        giftLog.claimedDay = date
        SharedFile.write(giftLog, to: Self.giftFile)
        return reward
    }

    private static let collectionsFile = "Shop/collections.json"
    private(set) var collectionLog = SharedFile.read(CollectionLog.self, from: collectionsFile) ?? CollectionLog()

    /// The bonus waits until every piece is owned, and is collected once.
    func canClaimBonus(_ collection: ShopCollection) -> Bool {
        !isSynced && collection.isComplete(owned) && !collectionLog.claimed.contains(collection.id)
    }

    @discardableResult
    func claimBonus(_ collection: ShopCollection) -> Bool {
        guard canClaimBonus(collection) else { return false }
        wallet.earn(collection.bonus)
        collectionLog.claimed.insert(collection.id)
        SharedFile.write(collectionLog, to: Self.collectionsFile)
        return true
    }

    // MARK: Buying

    /// The latest buy: the purchase moment plays for it and offers Undo for a few seconds.
    private(set) var lastPurchase: Purchase?

    /// Buys a set's missing pieces at the set price: the featured set or a bundle.
    @discardableResult
    func buy(_ set: some PieceSet) -> Bool {
        guard let quote = ShopOffers.price(of: set, owned: owned) else { return false }
        return record(.set(PieceSetId(set.id))) {
            $0.buy(set.itemIDs, cost: quote.price, title: set.name, at: .now)
        }
    }

    /// Deducts from the shared wallet. Gifts arrive wrapped and the partner unwraps them.
    @discardableResult
    func buy(_ item: ShopItem, asGift: Bool = false) -> Bool {
        let price = price(of: item)
        return record(.item(RoomItemId(item.id))) {
            $0.buy([item.id], cost: price, title: item.name, giftTo: asGift, at: .now)
        }
    }

    /// Takes a buy back within its Undo window: the coins return and the pieces it added leave the closet. The
    /// server keeps what it sold, so a synced buy has no Undo.
    @discardableResult
    func undo(_ purchase: Purchase, at now: Date = .now) -> Bool {
        guard !isSynced, lastPurchase?.id == purchase.id, purchase.canUndo(at: now) else { return false }
        wallet.update { $0.undo(purchase) }
        lastPurchase = nil
        return true
    }

    /// Buys an ink colour at its price. Unsynced, the server hears of it once Undo has passed (see `InkSync`).
    @discardableResult
    func buy(_ ink: PaletteInk) -> Bool {
        guard !ink.isOwned(owned) else { return false }
        return record(.ink(InkId(ink.id))) {
            $0.buy([ink.id], cost: ink.price, title: "\(ink.name) ink", kind: .ink, at: .now)
        }
    }

    /// The inks on sale, the free one first: the server's catalog once it has answered.
    var inks = PaletteInk.bundled

    /// A treat from the shared wallet.
    func treat() -> Bool {
        guard coins >= Self.treatPrice else { return false }
        wallet.update { $0.coins -= Self.treatPrice }
        care.fed()
        send(.treat)
        return true
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
        guard let sync, isSynced else { return }
        let request = WishRequest(item: RoomItemId(item.id), wished: wished)
        Task {
            if let shop = try? await sync.wish(request) { apply(shop) } else { await refresh() }
        }
    }

    private func record(_ offer: ShopOffer, _ buy: (inout Wallet) -> Purchase?) -> Bool {
        var made: Purchase?
        wallet.update { made = buy(&$0) }
        guard let made else { return false }
        lastPurchase = made
        care.notice()
        send(offer)
        return true
    }

    /// Sends a buy the wallet already shows. A lost answer is asked once more under the same id, which the server
    /// charges once; after a refusal the room is read again, which takes back what it did not record.
    private func send(_ offer: ShopOffer) {
        guard let sync, isSynced else { return }
        let request = OrderRequest(id: .make(), offer: offer)
        Task {
            for attempt in 1...2 {
                do throws(TransportError) {
                    apply(try await sync.order(request).shop)
                    return
                } catch {
                    guard case .network = error, attempt == 1 else { break }
                }
            }
            await refresh()
        }
    }

    // MARK: Server

    /// Follows the pair's room on the server, or, with nil, goes back to the phone's own wallet.
    func connect(_ sync: ShopSync?) async {
        self.sync = sync
        guard sync != nil else { return wallet.leaveSync() }
        await refresh()
    }

    /// Reads the pair's room again.
    func refresh() async {
        guard let sync, let shop = try? await sync.fetch() else { return }
        apply(shop)
    }

    private func apply(_ shop: ShopResponse) {
        // What the server doesn't sell stays as the phone has it.
        let ownOnly = wallet.wallet.owned.subtracting(Catalog.items.map(\.id)).filter { !PaletteInk.isInk($0) }
        wallet.mirror(
            coins: shop.balance,
            owned: Set(shop.items.map(\.rawValue) + shop.inks.map(\.rawValue)).union(ownOnly),
            wishlist: Set(shop.wishlist.map(\.rawValue)))
    }
}
