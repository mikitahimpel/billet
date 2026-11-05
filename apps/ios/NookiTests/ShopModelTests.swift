import Foundation
import Synchronization
import Testing
import Transport
import UIKit
import Wire
@testable import Billet

/// A server for one test: what it answers, and every request it was sent.
private nonisolated final class FakeRoom: Sendable {
    let shop: Mutex<ShopResponse>
    let orders = Mutex<[OrderRequest]>([])
    let earns = Mutex<[EarnRequest]>([])
    let reads = Mutex(0)
    /// How each order is answered; nil charges it.
    let refuse = Mutex<TransportError?>(nil)
    /// Orders and earns that fail with `.network` before one gets through.
    let drops = Mutex(0)

    init(_ shop: ShopResponse) {
        self.shop = Mutex(shop)
    }

    private func dropped() -> Bool {
        drops.withLock {
            guard $0 > 0 else { return false }
            $0 -= 1
            return true
        }
    }

    func sync(
        gift: @escaping @Sendable (OpenGiftRequest) async throws(TransportError) -> OpenGiftResponse = {
            (_) async throws(TransportError) in throw .network("unused")
        },
        bonus: @escaping @Sendable (ClaimBonusRequest) async throws(TransportError) -> ClaimBonusResponse = {
            (_) async throws(TransportError) in throw .network("unused")
        }
    ) -> ShopSync {
        ShopSync(
            fetch: { () async throws(TransportError) in
                self.reads.withLock { $0 += 1 }
                return self.shop.withLock { $0 }
            },
            order: { (request) async throws(TransportError) in
                self.orders.withLock { $0.append(request) }
                if self.dropped() { throw .network("lost") }
                if let refusal = self.refuse.withLock({ $0 }) { throw refusal }
                let shop = self.shop.withLock { $0 }
                return OrderResponse(
                    entry: CoinEntry(id: "spend:\(request.id.rawValue)", kind: .spend, amount: -60, ref: "x", at: 0),
                    shop: shop)
            },
            wish: { (_) async throws(TransportError) in self.shop.withLock { $0 } },
            openGift: gift,
            claimBonus: bonus,
            earn: { (request) async throws(TransportError) in
                self.earns.withLock { $0.append(request) }
                if self.dropped() { throw .network("lost") }
                return EarnResponse(balance: 123, entry: nil)
            })
    }
}

private nonisolated func room(
    _ balance: Int, items: [String] = ["lamp", "rug"], giftDay: String? = nil, bonuses: [String] = []
) -> ShopResponse {
    ShopResponse(
        balance: balance, inks: [.free], items: items.map(RoomItemId.init), wishlist: [], giftDay: giftDay,
        bonuses: bonuses)
}

/// Lets the model's tasks run until `done`, or gives up.
private func settle(_ done: () -> Bool) async {
    for _ in 0..<500 where !done() {
        try? await Task.sleep(for: .milliseconds(2))
    }
}

@MainActor
@Suite(.serialized) struct ShopModelTests {
    private let walletFile = "Tests/\(UUID().uuidString)-wallet.json"

    private func shop(coins: Int = 0) -> (ShopModel, WalletStore) {
        let wallet = WalletStore(file: walletFile)
        wallet.update { $0 = Wallet(coins: coins) }
        let care = CatCare(wallet: wallet, streak: StreakStore(file: "Tests/\(UUID().uuidString)-streak.json"))
        let model = ShopModel(wallet: wallet, couple: CoupleStore(), care: care)
        model.undoWindow = .zero
        model.retryDelay = .zero
        return (model, wallet)
    }

    private func cleanUp() {
        SharedFile.flush()
        try? FileManager.default.removeItem(at: SharedFile.url(walletFile))
    }

    @Test func theWalletShowsTheRoomAndForgetsItWithThePair() async {
        defer { cleanUp() }
        let (model, _) = shop(coins: 70)
        let server = FakeRoom(room(400, items: ["lamp", "rug", "tower"]))
        await model.connect(server.sync())
        #expect(model.isSynced)
        #expect(model.coins == 400)
        #expect(model.owned == ["lamp", "rug", "tower", InkId.free.rawValue])

        await model.connect(nil)
        #expect(!model.isSynced)
        #expect(model.coins == 0)
    }

    @Test func aPushedShopIsTakenOnlyWhileFollowingTheRoom() async {
        defer { cleanUp() }
        let (model, _) = shop(coins: 70)
        model.received(room(500, items: ["lamp", "rug", "tower"]))
        #expect(model.coins == 70)

        let server = room(100, items: ["lamp", "rug"])
        await model.connect(ShopSync(fetch: { server }, order: { _ throws(TransportError) in throw .status(500) }, wish: { _ in server }))
        model.received(room(500, items: ["lamp", "rug", "tower"]))
        #expect(model.coins == 500)
        #expect(model.owned.contains("tower"))
    }

    @Test func nothingIsBoughtWithoutAPair() throws {
        defer { cleanUp() }
        let (model, _) = shop(coins: 500)
        #expect(!model.buy(try #require(Catalog.item("yarn"))))
        #expect(!model.treat())
        #expect(model.coins == 500)
    }

    @Test func aBuyThePartnerOutspentOpensTheCoinsAndFinishesAfterATopUp() async throws {
        defer { cleanUp() }
        let (model, _) = shop()
        let server = FakeRoom(room(400))
        server.refuse.withLock { $0 = .api(.notEnoughCoins(needed: 60, have: 20)) }
        await model.connect(server.sync())
        let yarn = try #require(Catalog.item("yarn"))

        #expect(model.buy(yarn))
        #expect(model.owned.contains("yarn"))
        #expect(model.coins == 400 - model.price(of: yarn))
        server.shop.withLock { $0 = room(20) }
        await settle { model.coinsAsk != nil }

        #expect(model.coinsAsk?.missing == 40)
        #expect(model.coinsAsk?.retry?.offer == .item(RoomItemId("yarn")))
        #expect(model.refused == nil)
        #expect(model.lastPurchase == nil)
        #expect(!model.owned.contains("yarn"))
        #expect(model.coins == 20)

        // A pack bought: the room has the coins, and the same buy goes through in one tap.
        server.refuse.withLock { $0 = nil }
        server.shop.withLock { $0 = room(520) }
        await model.refresh()
        #expect(model.finish(try #require(model.coinsAsk?.retry)))
        #expect(model.owned.contains("yarn"))
        #expect(model.lastPurchase?.title == yarn.name)
        await settle { server.orders.withLock { $0.count } == 2 }
        #expect(server.orders.withLock { $0.count } == 2)
    }

    @Test func aBuyTheBalanceDoesNotCoverOpensTheCoinsBeforeAnyOrder() async throws {
        defer { cleanUp() }
        let (model, _) = shop()
        let server = FakeRoom(room(25))
        await model.connect(server.sync())
        let yarn = try #require(Catalog.item("yarn"))

        #expect(!model.buy(yarn))
        #expect(model.coinsAsk?.missing == model.price(of: yarn) - 25)
        #expect(model.coinsAsk?.retry?.title == yarn.name)
        #expect(model.lastPurchase == nil)
        #expect(server.orders.withLock { $0 }.isEmpty)

        let retry = try #require(model.coinsAsk?.retry)
        #expect(!model.finish(retry), "still short, so still not bought")
        server.shop.withLock { $0 = room(500) }
        await model.refresh()
        #expect(model.finish(retry))
        #expect(model.owned.contains("yarn"))
        await settle { !server.orders.withLock { $0 }.isEmpty }
        #expect(server.orders.withLock { $0 }.map(\.offer) == [.item(RoomItemId("yarn"))])
    }

    @Test func aTreatShortOfCoinsOpensTheCoinsToo() async {
        defer { cleanUp() }
        let (model, _) = shop()
        await model.connect(FakeRoom(room(3)).sync())
        #expect(!model.treat())
        #expect(model.coinsAsk?.missing == ShopModel.treatPrice - 3)
        #expect(model.coinsAsk?.retry?.kind == .treat)
    }

    @Test func anOrderAlreadyOwnedOrNoLongerSoldIsTakenBackToo() async throws {
        defer { cleanUp() }
        for refusal: TransportError in [.api(.alreadyOwned(itemId: "yarn")), .api(.notFound)] {
            let (model, _) = shop()
            let server = FakeRoom(room(400))
            server.refuse.withLock { $0 = refusal }
            await model.connect(server.sync())
            #expect(model.buy(try #require(Catalog.item("yarn"))))
            await settle { model.refused != nil }
            #expect(model.refused?.title == "Yarn Ball")
            #expect(model.coinsAsk == nil)
            #expect(model.coins == 400)
            #expect(!model.owned.contains("yarn"))
        }
    }

    @Test func aLostOrderIsAskedAgainUnderTheSameId() async throws {
        defer { cleanUp() }
        let (model, _) = shop()
        let server = FakeRoom(room(400))
        server.drops.withLock { $0 = 2 }
        await model.connect(server.sync())

        #expect(model.buy(try #require(Catalog.item("yarn"))))
        let purchase = try #require(model.lastPurchase)
        server.shop.withLock { $0 = room(340, items: ["lamp", "rug", "yarn"]) }
        await settle { model.pending.isEmpty }

        let orders = server.orders.withLock { $0 }
        #expect(orders.count == 3)
        #expect(Set(orders.map(\.id)) == [IdempotencyKey(purchase.id.uuidString)])
        #expect(orders.first?.offer == .item(RoomItemId("yarn")))
        #expect(model.refused == nil)
        #expect(model.coins == 340)
        #expect(model.owned.contains("yarn"))
    }

    @Test func anOrderLostOnEveryTryIsTakenBack() async throws {
        defer { cleanUp() }
        let (model, _) = shop()
        let server = FakeRoom(room(400))
        server.drops.withLock { $0 = 10 }
        await model.connect(server.sync())

        #expect(model.buy(try #require(Catalog.item("yarn"))))
        await settle { model.refused != nil }
        #expect(server.orders.withLock { $0.count } == ShopModel.attempts)
        #expect(model.coins == 400)
        #expect(!model.owned.contains("yarn"))
    }

    @Test func anUndoneBuyIsNeverOrdered() async throws {
        defer { cleanUp() }
        let (model, _) = shop()
        model.undoWindow = .milliseconds(150)
        let server = FakeRoom(room(400))
        await model.connect(server.sync())

        #expect(model.buy(try #require(Catalog.item("yarn"))))
        #expect(model.undo(try #require(model.lastPurchase)))
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.orders.withLock { $0.isEmpty })
        #expect(model.coins == 400)
        #expect(!model.owned.contains("yarn"))
    }

    @Test func aDealIsShownAtTheServersPriceAndOrderedOnThePhonesDay() async throws {
        defer { cleanUp() }
        let (model, _) = shop()
        let server = FakeRoom(room(2000))
        await model.connect(server.sync())
        let deal = try #require(model.offers.deals(on: .now).first { !model.owned.contains($0.itemID) })
        let item = try #require(Catalog.item(deal.itemID))
        #expect(model.price(of: item) == deal.price(of: item))
        #expect(model.price(of: item) < item.price)

        #expect(model.buy(item))
        await settle { !server.orders.withLock { $0.isEmpty } }
        let order = try #require(server.orders.withLock { $0.first })
        #expect(order.offer == .item(RoomItemId(item.id)))
        #expect(order.utcOffsetSeconds == TimeZone.current.secondsFromGMT(for: .now))
    }

    @Test func anInkIsAnOrderLikeAnyOther() async throws {
        defer { cleanUp() }
        let (model, _) = shop()
        let server = FakeRoom(room(400))
        await model.connect(server.sync())
        let rose = PaletteInk.bundled[1]

        #expect(model.buy(rose))
        #expect(model.lastPurchase?.kind == .ink)
        #expect(model.lastPurchase?.title == "Rose ink")
        #expect(!model.buy(rose))
        #expect(!model.buy(PaletteInk.free))
        await settle { !server.orders.withLock { $0.isEmpty } }
        #expect(server.orders.withLock { $0.first?.offer } == .ink(InkId("ink-rose")))
    }

    @Test func anEarnAsksTheServerAndShowsOnlyItsBalance() async {
        defer { cleanUp() }
        let (model, _) = shop()
        let server = FakeRoom(room(400))
        server.drops.withLock { $0 = 1 }
        await model.connect(server.sync())

        model.earn(.wishReceived(wish: "wish-1"))
        #expect(model.coins == 400)
        await settle { model.coins != 400 }

        let earns = server.earns.withLock { $0 }
        #expect(earns.map(\.event) == [.wishReceived(wish: "wish-1"), .wishReceived(wish: "wish-1")])
        #expect(model.coins == 123)
    }

    @Test func anEarnThatNeverArrivesChangesNothing() async {
        defer { cleanUp() }
        let (model, _) = shop()
        let server = FakeRoom(room(400))
        server.drops.withLock { $0 = 10 }
        await model.connect(server.sync())

        model.earn(.listTicked(item: "item-1"))
        await settle { server.earns.withLock { $0.count } == ShopModel.attempts }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(model.coins == 400)
    }

    @Test func theGiftIsOpenedOnTheServer() async throws {
        defer { cleanUp() }
        let (model, _) = shop()
        let today = ShopModel.localDay(.now)
        let server = FakeRoom(room(400))
        await model.connect(server.sync(gift: { (_) async throws(TransportError) in
            OpenGiftResponse(
                entry: CoinEntry(id: "gift:\(today)", kind: .gift, amount: 30, ref: today, at: 0),
                reward: .coins(30), shop: room(430, giftDay: today))
        }))
        #expect(model.canClaimGift())

        #expect(await model.openGift() == .opened(.coins(30)))
        #expect(model.coins == 430)
        #expect(!model.canClaimGift())
    }

    @Test func aTakenGiftReadsTheRoomAndShowsItOpened() async throws {
        defer { cleanUp() }
        let (model, _) = shop()
        let today = ShopModel.localDay(.now)
        let server = FakeRoom(room(400))
        await model.connect(server.sync(gift: { (_) async throws(TransportError) in
            throw .api(.giftTaken(day: today))
        }))
        server.shop.withLock { $0 = room(430, giftDay: today) }

        #expect(await model.openGift() == .taken)
        #expect(!model.canClaimGift())
        #expect(model.coins == 430)
    }

    @Test func aBonusTheServerRefusesReadsTheRoomAgain() async throws {
        defer { cleanUp() }
        let (model, _) = shop()
        let corner = try #require(Catalog.collections.first { $0.id == "mochis-corner" })
        let cornerID = corner.id
        let server = FakeRoom(room(400, items: ["lamp", "rug"] + corner.itemIDs))
        await model.connect(server.sync(bonus: { (_) async throws(TransportError) in
            throw .api(.collectionIncomplete(collection: cornerID))
        }))
        #expect(model.canClaimBonus(corner))
        server.shop.withLock { $0 = room(400, items: ["lamp", "rug"]) }

        #expect(await model.claimBonus(corner) == false)
        #expect(!model.canClaimBonus(corner))
        #expect(model.coins == 400)
    }

    @Test func aBonusThePartnerCollectedShowsAsCollected() async throws {
        defer { cleanUp() }
        let (model, _) = shop()
        let corner = try #require(Catalog.collections.first { $0.id == "mochis-corner" })
        let cornerID = corner.id
        let items = ["lamp", "rug"] + corner.itemIDs
        let server = FakeRoom(room(400, items: items))
        await model.connect(server.sync(bonus: { (_) async throws(TransportError) in
            throw .api(.bonusTaken(collection: cornerID))
        }))
        server.shop.withLock { $0 = room(500, items: items, bonuses: [cornerID]) }

        #expect(await model.claimBonus(corner) == false)
        #expect(model.bonuses == [cornerID])
        #expect(!model.canClaimBonus(corner))
        #expect(model.coins == 500)
    }

    @Test func aCollectedBonusShowsTheServersBalance() async throws {
        defer { cleanUp() }
        let (model, _) = shop()
        let corner = try #require(Catalog.collections.first { $0.id == "mochis-corner" })
        let cornerID = corner.id
        let items = ["lamp", "rug"] + corner.itemIDs
        let server = FakeRoom(room(400, items: items))
        await model.connect(server.sync(bonus: { (_) async throws(TransportError) in
            ClaimBonusResponse(
                entry: CoinEntry(id: "bonus:\(cornerID)", kind: .bonus, amount: 100, ref: cornerID, at: 0),
                shop: room(500, items: items, bonuses: [cornerID]))
        }))

        #expect(await model.claimBonus(corner))
        #expect(model.coins == 500)
        #expect(model.bonuses == [corner.id])
        #expect(!model.canClaimBonus(corner))
    }

    @Test func theHistoryIsTheLatestEntriesNewestFirst() async {
        defer { cleanUp() }
        let (model, _) = shop()
        let entries = (0..<150).map { CoinEntry(id: "earn:e\($0)", kind: .earn, amount: 1, ref: "e\($0)", at: Int64($0)) }
        var sync = FakeRoom(room(150)).sync()
        sync.coins = { (after) async throws(TransportError) in
            let start = after.flatMap { id in entries.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0
            return CoinsResponse(balance: 150, entries: Array(entries[start..<min(start + 100, entries.count)]))
        }
        await model.connect(sync)
        await model.loadHistory()
        #expect(model.history.map(\.id) == (140..<150).reversed().map { "earn:e\($0)" })
    }
}

@MainActor
@Suite(.serialized) struct EarnTests {
    @Test func whatStaysOnThisPhoneEarnsAndWhatGoesToThePartnerDoesNot() throws {
        var earned: [EarnEvent] = []
        let moments = MomentStore(), notes = NoteStore()
        let journal = Journal(
            moments: moments, notes: notes, streak: StreakStore(file: "Tests/\(UUID().uuidString)-streak.json"),
            couple: CoupleStore()) { earned.append($0) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }

        #expect(journal.addNote(text: "dinner at 8?", paper: .sky))
        #expect(journal.addMoment(image, caption: "shared", shares: true))
        #expect(earned.isEmpty)

        let notesBefore = Set(notes.notes.map(\.id)), momentsBefore = Set(moments.moments.map(\.id))
        #expect(journal.addNote(doodle: image, paper: .sky))
        #expect(journal.addMoment(image, caption: "keepsake"))
        let doodle = try #require(notes.notes.first { !notesBefore.contains($0.id) })
        let keepsake = try #require(moments.moments.first { !momentsBefore.contains($0.id) })
        #expect(earned == [.noteAdded(note: doodle.id.uuidString), .momentAdded(moment: keepsake.id.uuidString)])

        for note in notes.notes where note.text == "dinner at 8?" || note.id == doodle.id { notes.delete(note) }
        for moment in moments.moments where moment.caption == "shared" || moment.id == keepsake.id {
            moments.delete(moment)
        }
    }

    @Test func theUsTabAsksForItsEarnsOncePerThing() throws {
        let path = "Tests/\(UUID().uuidString)-us.json"
        defer {
            SharedFile.flush()
            try? FileManager.default.removeItem(at: SharedFile.url(path))
        }
        var earned: [EarnEvent] = []
        let us = UsStore(file: path) { earned.append($0) }

        let wish = WishItem(owner: "L", title: "Scarf")
        us.upsertWish(wish)
        us.markReceived(wish.id, by: "L")
        us.markReceived(wish.id, by: "L")

        let idea = try #require(DateIdea.all.first)
        us.swipe(idea.id, liked: true, by: "L")
        us.swipe(idea.id, liked: true, by: "M")
        us.swipe(idea.id, liked: true, by: "M")

        let plan = PlannedDate(ideaID: idea.id, date: .now, organizer: "L")
        us.upsertPlan(plan)
        us.rate(plan.id, hearts: 3)
        us.rate(plan.id, hearts: 2)

        #expect(earned == [
            .wishReceived(wish: wish.id.uuidString), .dateMatched(idea: String(idea.id)),
            .dateRated(plan: plan.id.uuidString),
        ])
    }
}
