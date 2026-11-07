import Foundation
import ShopInterface
import Testing
import Wire

@testable import FeatureShop

typealias M = ShopMachine

private let lampID = UUID()
private let placedAt = Date(timeIntervalSince1970: 1_700_000_000)
private let lamp = ShopOrder(
  offer: .item(RoomItemId("lamp")), itemIDs: ["lamp"], cost: 140, title: "Lamp")
private let gift = ShopOrder(
  offer: .item(RoomItemId("rug")), itemIDs: ["rug"], cost: 180, title: "Rug", asGift: true)

private func room(
  _ balance: Int, items: [String] = ["lamp0"], giftDay: String? = nil, bonuses: [String] = []
) -> ShopResponse {
  ShopResponse(
    balance: balance, inks: [.free], items: items.map(RoomItemId.init), wishlist: [],
    giftDay: giftDay, bonuses: bonuses)
}

/// A shop following its room, read once.
private func open(_ balance: Int, items: [String] = ["lamp0"]) -> M.PairShop {
  var shop = M.PairShop(mirror: M.Mirror(balance: 0, owned: [], wishlist: []))
  _ = shop.read()
  let (state, _) = M.transition(.open(shop), .fetched(room(balance, items: items), request: 1))
  guard case .open(let read) = state else { fatalError("not open") }
  return read
}

private func shop(_ state: M.State) -> M.PairShop {
  guard case .open(let shop) = state else { fatalError("not open") }
  return shop
}

@Suite struct ShopMachineTests {
  @Test func followingARoomReadsItAndLeavingForgetsIt() {
    let last = M.Mirror(balance: 70, owned: ["lamp0"], wishlist: [])
    var (state, outputs) = M.transition(.initial, .connected(last: last))
    #expect(outputs == [.loadInks, .fetch(request: 1)])
    #expect(shop(state).coins == 70, "the wallet file's coins until the room answers")

    (state, outputs) = M.transition(
      state, .fetched(room(400, items: ["lamp0", "tower"]), request: 1))
    #expect(shop(state).coins == 400)
    #expect(shop(state).owned == ["lamp0", "tower", InkId.free.rawValue])
    #expect(
      outputs == [
        .mirror(
          M.Mirror(balance: 400, owned: ["lamp0", "tower", InkId.free.rawValue], wishlist: []))
      ])

    (state, outputs) = M.transition(state, .disconnected)
    #expect(state == .offline(refused: nil, ask: nil))
    #expect(outputs == [.leaveWallet])
  }

  @Test func aStaleReadChangesNothing() {
    var (state, _) = M.transition(
      .initial, .connected(last: M.Mirror(balance: 0, owned: [], wishlist: [])))
    (state, _) = M.transition(state, .refreshAsked)
    #expect(shop(state).fetch == .reading(request: 2))
    let (next, outputs) = M.transition(state, .fetched(room(999), request: 1))
    #expect(next == state)
    #expect(outputs.isEmpty)
  }

  @Test func aPushedShopIsTakenOnlyWhileFollowingTheRoom() {
    let (offline, none) = M.transition(.initial, .pushed(room(500)))
    #expect(offline == .initial)
    #expect(none.isEmpty)

    let (state, outputs) = M.transition(
      .open(open(100)), .pushed(room(500, items: ["lamp0", "tower"])))
    #expect(shop(state).coins == 500)
    #expect(shop(state).owned.contains("tower"))
    #expect(outputs == [.mirror(shop(state).mirror)])
  }

  @Test func aBuyWithoutARoomIsRefusedOutLoud() {
    let (state, outputs) = M.transition(.initial, .buyTapped(lamp, id: lampID, at: placedAt))
    guard case .offline(let refused, _) = state else {
      Issue.record("left offline")
      return
    }
    #expect(refused?.title == "Lamp")
    #expect(outputs.isEmpty)

    let (treat, treatOutputs) = M.transition(.initial, .treatTapped(id: UUID(), at: placedAt))
    #expect(treat == .initial)
    #expect(treatOutputs.isEmpty)
  }

  @Test func aBuyShowsAtOnceWaitsOutUndoThenIsOrdered() {
    var (state, outputs) = M.transition(
      .open(open(400)), .buyTapped(lamp, id: lampID, at: placedAt))
    #expect(outputs == [.wait(lampID), .catNoticed])
    #expect(shop(state).coins == 260)
    #expect(shop(state).owned.contains("lamp"))
    #expect(shop(state).pending.map(\.stage) == [.undoable])
    guard case .placed(let placed) = shop(state).moment else {
      Issue.record("no moment")
      return
    }
    #expect(placed.id == lampID)

    (state, outputs) = M.transition(state, .undoWindowPassed(lampID))
    #expect(shop(state).pending.map(\.stage) == [.ordering])
    #expect(outputs == [.order(shop(state).pending[0])])

    (state, outputs) = M.transition(state, .ordered(lampID, room(260, items: ["lamp0", "lamp"])))
    #expect(shop(state).pending.isEmpty)
    #expect(shop(state).coins == 260)
    #expect(outputs == [.mirror(shop(state).mirror)])
    #expect(shop(state).moment == .placed(placed), "the moment stays for its countdown")
  }

  @Test func anUndoneBuyIsNeverOrderedAndALateUndoChangesNothing() {
    var (state, _) = M.transition(.open(open(400)), .buyTapped(lamp, id: lampID, at: placedAt))
    (state, _) = M.transition(state, .undoTapped(lampID))
    #expect(shop(state).pending.isEmpty)
    #expect(shop(state).moment == nil)
    #expect(shop(state).coins == 400)
    let (same, none) = M.transition(state, .undoWindowPassed(lampID))
    #expect(same == state)
    #expect(none.isEmpty)

    (state, _) = M.transition(.open(open(400)), .buyTapped(lamp, id: lampID, at: placedAt))
    (state, _) = M.transition(state, .undoWindowPassed(lampID))
    let (late, lateOutputs) = M.transition(state, .undoTapped(lampID))
    #expect(late == state)
    #expect(lateOutputs.isEmpty)
  }

  @Test func aGiftIsMarkedGiftedOnceCharged() {
    var (state, _) = M.transition(.open(open(400)), .buyTapped(gift, id: lampID, at: placedAt))
    #expect(shop(state).giftedPending == ["rug"])
    (state, _) = M.transition(state, .undoWindowPassed(lampID))
    let outputs: [M.Output]
    (state, outputs) = M.transition(state, .ordered(lampID, room(220, items: ["lamp0", "rug"])))
    #expect(outputs == [.markGifted(["rug"]), .mirror(shop(state).mirror)])
  }

  @Test func aBuyTheBalanceDoesNotCoverOpensTheCoinsBeforeAnyOrder() {
    let (state, outputs) = M.transition(.open(open(25)), .buyTapped(lamp, id: lampID, at: placedAt))
    #expect(outputs.isEmpty)
    #expect(shop(state).pending.isEmpty)
    #expect(shop(state).ask?.missing == 115)
    #expect(shop(state).ask?.retry == lamp)

    let (short, shortOutputs) = M.transition(.open(open(3)), .treatTapped(id: UUID(), at: placedAt))
    #expect(shortOutputs.isEmpty)
    #expect(shop(short).ask?.missing == M.treatPrice - 3)
    #expect(shop(short).ask?.retry?.kind == .treat)
  }

  @Test func anOwnedPieceIsNotBoughtAgain() {
    let (state, outputs) = M.transition(
      .open(open(400, items: ["lamp"])), .buyTapped(lamp, id: lampID, at: placedAt))
    #expect(state == .open(open(400, items: ["lamp"])))
    #expect(outputs.isEmpty)
  }

  @Test func aBuyThePartnerOutspentOpensTheCoinsWithTheSameBuy() {
    var (state, _) = M.transition(.open(open(400)), .buyTapped(lamp, id: lampID, at: placedAt))
    (state, _) = M.transition(state, .undoWindowPassed(lampID))
    let outputs: [M.Output]
    (state, outputs) = M.transition(
      state, .orderFailed(lampID, .notEnoughCoins(needed: 140, have: 20)))
    #expect(shop(state).pending.isEmpty)
    #expect(shop(state).moment == nil)
    #expect(shop(state).ask?.missing == 120)
    #expect(shop(state).ask?.retry == lamp)
    #expect(outputs == [.fetch(request: 2)], "the room is read again")
  }

  @Test func aRefusedOrderIsTakenBackAndSaidSo() {
    var (state, _) = M.transition(.open(open(400)), .buyTapped(lamp, id: lampID, at: placedAt))
    (state, _) = M.transition(state, .undoWindowPassed(lampID))
    let outputs: [M.Output]
    (state, outputs) = M.transition(state, .orderFailed(lampID, .alreadyOwned))
    guard case .refused(let refused) = shop(state).moment else {
      Issue.record("not refused")
      return
    }
    #expect(refused.id == lampID)
    #expect(shop(state).coins == 400)
    #expect(!shop(state).owned.contains("lamp"))
    #expect(outputs == [.fetch(request: 2)])
  }

  @Test func aTreatIsOrderedAtOnceAndEaten() {
    let id = UUID()
    let (state, outputs) = M.transition(.open(open(400)), .treatTapped(id: id, at: placedAt))
    #expect(shop(state).pending.map(\.stage) == [.ordering])
    #expect(shop(state).coins == 390)
    #expect(shop(state).moment == nil)
    #expect(outputs == [.order(shop(state).pending[0]), .catFed])

    let (lost, lostOutputs) = M.transition(state, .orderFailed(id, .unavailable))
    #expect(shop(lost).moment == nil, "a lost treat has no purchase moment")
    #expect(lostOutputs == [.fetch(request: 2)])
  }

  @Test func anEarnAsksTheServerAndShowsOnlyItsBalance() {
    let (offline, none) = M.transition(.initial, .earnAsked(.wishReceived(wish: "w")))
    #expect(offline == .initial)
    #expect(none.isEmpty)

    let (state, outputs) = M.transition(.open(open(400)), .earnAsked(.wishReceived(wish: "w")))
    #expect(state == .open(open(400)))
    #expect(outputs == [.earn(.wishReceived(wish: "w"))])
    let (paid, paidOutputs) = M.transition(state, .earned(balance: 123))
    #expect(shop(paid).coins == 123)
    #expect(paidOutputs == [.mirrorBalance(123)])
  }

  @Test func theGiftIsOpenedOnTheServer() {
    var (state, outputs) = M.transition(.open(open(400)), .giftTapped(day: "2026-11-07"))
    #expect(outputs == [.openGift])
    #expect(shop(state).gift == .opening(day: "2026-11-07"))
    let (twice, none) = M.transition(state, .giftTapped(day: "2026-11-07"))
    #expect(twice == state)
    #expect(none.isEmpty)

    (state, outputs) = M.transition(
      state, .giftOpened(.coins(30), room(430, giftDay: "2026-11-07")))
    #expect(shop(state).gift == .opened(.coins(30)))
    #expect(shop(state).coins == 430)
    (state, _) = M.transition(state, .giftShown)
    #expect(shop(state).gift == .idle)
    let (again, againOutputs) = M.transition(state, .giftTapped(day: "2026-11-07"))
    #expect(again == state)
    #expect(againOutputs.isEmpty, "opened today already")
  }

  @Test func aTakenGiftReadsTheRoomAndShowsItOpened() {
    var (state, _) = M.transition(.open(open(400)), .giftTapped(day: "2026-11-07"))
    let outputs: [M.Output]
    (state, outputs) = M.transition(state, .giftFailed(.giftTaken(day: "2026-11-07")))
    #expect(outputs == [.fetch(request: 2)])
    #expect(shop(state).gift == .checking(day: "2026-11-07", request: 2))
    (state, _) = M.transition(state, .fetched(room(430, giftDay: "2026-11-07"), request: 2))
    #expect(shop(state).gift == .taken)
    #expect(shop(state).coins == 430)

    var (down, _) = M.transition(.open(open(400)), .giftTapped(day: "2026-11-07"))
    (down, _) = M.transition(down, .giftFailed(.unavailable))
    (down, _) = M.transition(down, .fetchFailed(request: 2))
    #expect(shop(down).gift == .failed)
  }

  @Test func aBonusWaitsForEveryPieceAndIsCollectedOnce() {
    let pieces = ["yarn", "mouse"]
    let (incomplete, none) = M.transition(
      .open(open(400, items: ["yarn"])), .bonusTapped(collection: "corner", itemIDs: pieces))
    #expect(incomplete == .open(open(400, items: ["yarn"])))
    #expect(none.isEmpty)

    var (state, outputs) = M.transition(
      .open(open(400, items: pieces)), .bonusTapped(collection: "corner", itemIDs: pieces))
    #expect(outputs == [.claimBonus(collection: "corner")])
    (state, outputs) = M.transition(
      state, .bonusClaimed(room(500, items: pieces, bonuses: ["corner"])))
    #expect(shop(state).bonus == .claimed(collection: "corner"))
    #expect(shop(state).bonuses == ["corner"])
    #expect(shop(state).coins == 500)
    (state, _) = M.transition(state, .bonusShown)
    let (again, againOutputs) = M.transition(
      state, .bonusTapped(collection: "corner", itemIDs: pieces))
    #expect(again == state)
    #expect(againOutputs.isEmpty)
  }

  @Test func aBonusThePartnerCollectedShowsAsCollectedAfterTheRoomIsReadAgain() {
    let pieces = ["yarn", "mouse"]
    var (state, _) = M.transition(
      .open(open(400, items: pieces)), .bonusTapped(collection: "corner", itemIDs: pieces))
    let outputs: [M.Output]
    (state, outputs) = M.transition(state, .bonusFailed(.bonusTaken))
    #expect(outputs == [.fetch(request: 2)])
    #expect(shop(state).bonuses == ["corner"])
    #expect(shop(state).bonus == .refusing(collection: "corner", request: 2))
    (state, _) = M.transition(
      state, .fetched(room(500, items: pieces, bonuses: ["corner"]), request: 2))
    #expect(shop(state).bonus == .refused(collection: "corner"))
    #expect(shop(state).coins == 500)
  }

  @Test func theHistoryIsAskedAndKept() {
    let entries = [CoinEntry(id: "earn:1", kind: .earn, amount: 1, ref: "1", at: 1)]
    var (state, outputs) = M.transition(.open(open(400)), .historyAsked(limit: 10))
    #expect(outputs == [.loadHistory(limit: 10)])
    (state, outputs) = M.transition(state, .historyLoaded(entries, balance: 150))
    #expect(shop(state).history == entries)
    #expect(shop(state).coins == 150)
    #expect(outputs == [.mirrorBalance(150)])
  }

  @Test func theCoinsSheetOpensAndClosesAnywhere() {
    let ask = CoinsAsk(missing: 0, retry: nil)
    var (state, _) = M.transition(.initial, .coinsAsked(ask))
    #expect(state == .offline(refused: nil, ask: ask))
    (state, _) = M.transition(state, .coinsSheetClosed)
    #expect(state == .initial)

    (state, _) = M.transition(.open(open(400)), .coinsAsked(ask))
    #expect(shop(state).ask == ask)
    (state, _) = M.transition(
      state, .connected(last: M.Mirror(balance: 1, owned: [], wishlist: [])))
    #expect(shop(state).ask == ask, "a new room keeps the sheet")
    (state, _) = M.transition(state, .disconnected)
    #expect(state == .offline(refused: nil, ask: ask))
  }

  @Test(arguments: [
    (M.State.initial, M.Event.refreshAsked),
    (.initial, .undoTapped(lampID)),
    (.initial, .giftTapped(day: "2026-11-07")),
    (.initial, .bonusTapped(collection: "corner", itemIDs: [])),
    (.initial, .historyAsked(limit: 10)),
    (.initial, .fetched(room(400), request: 1)),
    (.initial, .ordered(lampID, room(400))),
    (.initial, .earned(balance: 5)),
    (.open(open(400)), .ordered(lampID, room(400))),
    (.open(open(400)), .orderFailed(lampID, .unavailable)),
    (.open(open(400)), .undoWindowPassed(lampID)),
    (.open(open(400)), .giftOpened(.coins(1), room(400))),
    (.open(open(400)), .giftFailed(.unavailable)),
    (.open(open(400)), .giftShown),
    (.open(open(400)), .bonusClaimed(room(400))),
    (.open(open(400)), .bonusFailed(.unavailable)),
    (.open(open(400)), .bonusShown),
    (.open(open(400)), .historyLoaded([], balance: 1)),
    (.open(open(400)), .fetchFailed(request: 7)),
    (.open(open(400)), .buyTapped(lamp, id: lampID, at: placedAt)),
  ])
  func rejectedOrSettled(state: M.State, event: M.Event) {
    let (next, outputs) = M.transition(state, event)
    if case .buyTapped = event {
      // The one accepted pair above, kept to show the table catches a wrong entry.
      #expect(next != state)
      return
    }
    #expect(next == state)
    #expect(outputs.isEmpty)
  }
}
