import Foundation
import ShopInterface
import Testing
import Wire

@testable import FeatureShop

private nonisolated let orderID = UUID()
private nonisolated let at = Date(timeIntervalSince1970: 1_700_000_000)
private nonisolated let lamp = ShopOrder(
  offer: .item(RoomItemId("lamp")), itemIDs: ["lamp"], cost: 140, title: "Lamp")
private nonisolated let ink = ShopOrder(
  offer: .ink(InkId("ink-plum")), itemIDs: ["ink-plum"], cost: 60, title: "Plum ink", kind: .ink)
private nonisolated let free = ShopOrder(
  offer: .item(RoomItemId("moss")), itemIDs: ["moss"], cost: 0, title: "Moss")

private nonisolated func room(_ balance: Int) -> M.State {
  var shop = M.PairShop(mirror: M.Mirror(balance: 0, owned: [], wishlist: []))
  _ = shop.read()
  let response = ShopResponse(
    balance: balance, inks: [.free], items: [], wishlist: [], giftDay: nil, bonuses: [])
  let (state, _) = M.transition(.open(shop), .fetched(response, request: 1))
  return state
}

private nonisolated func shop(_ state: M.State) -> M.PairShop {
  guard case .open(let shop) = state else { fatalError("not open") }
  return shop
}

/// The states an App Store refund can leave: the balance is the room's signed answer.
@Suite nonisolated struct CoinDebtMachineTests {
  @Test func aRefundBelowZeroIsADebtNotAnEmptyPurse() {
    let state = shop(room(-540))
    #expect(state.balance == -540)
    #expect(state.coins == 0)
    #expect(state.debt == 540)
    #expect(shop(room(0)).debt == 0)
    #expect(shop(room(60)).debt == 0)
  }

  @Test(arguments: [
    ("a piece", M.Event.buyTapped(lamp, id: orderID, at: at), 680),
    ("an ink", M.Event.buyTapped(ink, id: orderID, at: at), 600),
    ("a free piece", M.Event.buyTapped(free, id: orderID, at: at), 540),
    ("a treat", M.Event.treatTapped(id: orderID, at: at), M.treatPrice + 540),
  ])
  func everySpendIsRefusedWhileTheBalanceIsNegative(_: String, _ event: M.Event, _ missing: Int) {
    let (state, outputs) = M.transition(room(-540), event)
    #expect(outputs.isEmpty, "nothing is ordered, nothing is wished, the cat is not told")
    #expect(shop(state).pending.isEmpty)
    #expect(shop(state).moment == nil)
    #expect(shop(state).ask?.missing == missing, "the sheet opens at what the debt and price need")
    #expect(shop(state).balance == -540, "a refused spend changes nothing")
  }

  @Test func earningPaysTheDebtDownAndSpendingWaitsForTheWholePrice() {
    var (state, outputs) = M.transition(room(-540), .earned(balance: -500))
    #expect(outputs == [.mirrorBalance(-500)])
    #expect(shop(state).debt == 500)

    (state, outputs) = M.transition(state, .buyTapped(lamp, id: orderID, at: at))
    #expect(outputs.isEmpty)
    #expect(shop(state).ask?.missing == 640)

    (state, _) = M.transition(state, .earned(balance: 0))
    #expect(shop(state).debt == 0)
    (state, outputs) = M.transition(state, .buyTapped(ink, id: orderID, at: at))
    #expect(shop(state).ask?.missing == 60, "covered, but not yet the price")
    #expect(outputs.isEmpty)

    (state, _) = M.transition(state, .earned(balance: 60))
    (state, outputs) = M.transition(state, .buyTapped(ink, id: orderID, at: at))
    #expect(shop(state).pending.map(\.id) == [orderID])
    #expect(!outputs.isEmpty)
  }

  @Test func aBuyTheRoomRefusesForADebtOpensTheSheetAtWhatIsStillMissing() {
    var (state, _) = M.transition(room(400), .buyTapped(ink, id: orderID, at: at))
    (state, _) = M.transition(state, .orderFailed(orderID, .notEnoughCoins(needed: 60, have: -540)))
    (state, _) = M.transition(
      state,
      .fetched(
        ShopResponse(
          balance: -540, inks: [.free], items: [], wishlist: [], giftDay: nil, bonuses: []),
        request: 2))
    #expect(shop(state).ask?.missing == 600)
    #expect(shop(state).ask?.retry == ink)
  }

  @Test func spendingNeedsNoDebtAndTheWholePrice() {
    let state = shop(room(-540))
    var model = state
    #expect(model.canSpend(0) == false)
    model.mirror.balance = 140
    #expect(model.canSpend(140))
    #expect(model.canSpend(141) == false)
  }
}

@Suite struct CoinDebtNoteTests {
  private func entry(_ kind: CoinEntryKind, _ amount: Int, _ id: String) -> CoinEntry {
    CoinEntry(id: id, kind: kind, amount: amount, ref: "pack", at: 0)
  }

  @Test func thereIsNoNoteUnlessTheBalanceIsBelowZero() {
    #expect(CoinDebt(balance: 0, history: []) == nil)
    #expect(CoinDebt(balance: 25, history: [entry(.refund, -550, "refund:1")]) == nil)
  }

  @Test func itNamesWhatTheLatestRefundTookBackAndWhatIsOwed() throws {
    let history = [
      entry(.earn, 5, "earn:a"), entry(.refund, -550, "refund:1"),
      entry(.purchase, 550, "purchase:1"),
    ]
    let debt = try #require(CoinDebt(balance: -480, history: history))
    #expect(debt.owed == 480)
    #expect(debt.refunded == 550)
    #expect(debt.title == "A refund took back 550 coins")
    #expect(debt.detail.contains("New coins you earn cover it first"))
    #expect(debt.detail.contains("never expire"))
  }

  @Test func withoutTheHistoryYetItSaysWhatIsOwed() throws {
    let debt = try #require(CoinDebt(balance: -480, history: []))
    #expect(debt.refunded == 480)
  }

  @Test func theHistoryReadsRefundsAndTheNewKindsAsWhatTheyAre() {
    let offers = ShopOffers(pairSeed: "L+M", cat: "Mochi")
    let refund = CoinLine(entry(.refund, -550, "refund:1"), offers: offers)
    #expect(refund.title == "Refund")
    #expect(refund.amount == "−550")
    #expect(!refund.isGain)
    #expect(CoinLine(entry(.purchase, 550, "purchase:1"), offers: offers).title == "Coins bought")
    #expect(CoinLine(entry(.buy, 550, "buy:1"), offers: offers).title == "Coins bought")
    #expect(CoinLine(entry(.admin, 100, "admin:1"), offers: offers).title == "Coins from support")
    #expect(CoinLine(entry(.unknown, 7, "x:1"), offers: offers).title == "Coins added")
  }
}
