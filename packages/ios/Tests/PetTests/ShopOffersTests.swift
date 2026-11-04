import Foundation
import Testing

@testable import Pet

/// The day's deals, the week's bundle and the free gift: the same on both phones, changing only
/// when their timers say.
@Suite("Shop offers")
struct ShopOffersTests {
  private let catalog = ShopCatalog.standard
  /// Wednesday 4 November 2026, 15:00 UTC.
  private let wednesday = Date(timeIntervalSince1970: 1_793_804_400)

  @Test func bothPhonesOfAPairSeeTheSameOffers() {
    let mine = ShopOffers(pair: "K7MPQ2X9RT", now: wednesday, catalog: catalog)
    // The partner's clock is a few hours off, the same UTC day.
    let theirs = ShopOffers(
      pair: "K7MPQ2X9RT", now: wednesday.addingTimeInterval(-3 * 3_600), catalog: catalog)
    #expect(mine == theirs)
    #expect(mine.deals.count == ShopOffers.dealCount)
    #expect(Set(mine.deals.map(\.id)).count == ShopOffers.dealCount)
  }

  @Test func anotherPairGetsOtherDeals() {
    let pairs = ["AAAAAAAAAA", "BBBBBBBBBB", "CCCCCCCCCC", "DDDDDDDDDD"]
    let deals = Set(pairs.map { ShopOffers(pair: $0, now: wednesday, catalog: catalog).deals })
    #expect(deals.count > 1)
  }

  @Test func dealsChangeAtUTCMidnightAndTheTimerSaysSo() {
    let today = ShopOffers(pair: "K7MPQ2X9RT", now: wednesday, catalog: catalog)
    let midnight = Date(timeIntervalSince1970: 1_793_836_800)
    #expect(today.dayEnds == midnight)
    let lastSecond = ShopOffers(
      pair: "K7MPQ2X9RT", now: midnight.addingTimeInterval(-1), catalog: catalog)
    #expect(lastSecond.deals == today.deals)
    #expect(lastSecond.gift == today.gift)
    let tomorrow = ShopOffers(pair: "K7MPQ2X9RT", now: midnight, catalog: catalog)
    #expect(tomorrow.gift.id != today.gift.id)
  }

  @Test func theFeaturedBundleChangesOnMondayInUTC() {
    let offers = ShopOffers(pair: "K7MPQ2X9RT", now: wednesday, catalog: catalog)
    // Monday 9 November 2026, 00:00 UTC.
    let monday = Date(timeIntervalSince1970: 1_794_182_400)
    #expect(offers.featuredEnds == monday)
    let sunday = ShopOffers(
      pair: "K7MPQ2X9RT", now: monday.addingTimeInterval(-1), catalog: catalog)
    #expect(sunday.featured == offers.featured)
    #expect(ShopRotation.week(of: monday) == ShopRotation.week(of: wednesday) + 1)
  }

  @Test func theStarterIsNeverFeaturedAndTheFeaturedIsNotListedTwice() throws {
    for day in 0..<60 {
      let offers = ShopOffers(
        pair: "K7MPQ2X9RT", now: wednesday.addingTimeInterval(Double(day) * 86_400),
        catalog: catalog)
      let featured = try #require(offers.featured)
      #expect(!featured.isStarter)
      #expect(!offers.bundles.contains(featured))
    }
  }

  @Test func aDealCostsLessThanUsual() {
    let offers = ShopOffers(pair: "K7MPQ2X9RT", now: wednesday, catalog: catalog)
    for deal in offers.deals {
      #expect(deal.price < deal.item.price)
      #expect(deal.price == deal.item.price * (100 - deal.discount) / 100)
      #expect(ShopOffers.dealDiscounts.contains(deal.discount))
    }
  }

  @Test func everyBundleItemIsSoldAndTheLabsOnesOnlyWithLabs() {
    for bundle in ShopBundle.all {
      let items = bundle.items(in: catalog)
      #expect(!items.isEmpty)
      let missing = bundle.itemIDs.filter { catalog.anyItem($0) == nil }
      #expect(missing.allSatisfy { $0.hasPrefix("furniture-idol-") }, "\(bundle.id): \(missing)")
      #expect(bundle.itemIDs.allSatisfy { catalog.withIdolProps.anyItem($0) != nil })
    }
  }

  @Test func aBundleCostsLessThanItsParts() {
    for bundle in ShopBundle.all {
      let items = bundle.items(in: catalog)
      #expect(bundle.price(of: items) < ShopBundle.sum(of: items))
    }
  }

  @Test func theGiftIsSomeStampsOrATreat() {
    for day in 0..<40 {
      let offers = ShopOffers(
        pair: "K7MPQ2X9RT", now: wednesday.addingTimeInterval(Double(day) * 86_400),
        catalog: catalog)
      switch offers.gift.reward {
      case .stamps(let amount): #expect((10...20).contains(amount))
      case .item(let id): #expect(catalog.item(id)?.isConsumable == true)
      }
    }
  }

  @Test func theSameSeedGivesTheSameSequence() {
    var a = StableRandom(seed: "pair|day|1")
    var b = StableRandom(seed: "pair|day|1")
    var c = StableRandom(seed: "pair|day|2")
    let first = (0..<4).map { _ in a.next() }
    #expect(first == (0..<4).map { _ in b.next() })
    #expect(first != (0..<4).map { _ in c.next() })
  }
}

/// Bundles, deals, the daily gift and gifts for the partner, bought with one tap and taken back
/// within the undo window.
@MainActor
@Suite("Shop selling")
struct ShopSellingTests {
  private let catalog = ShopCatalog.standard
  private var nook: ShopBundle { ShopBundle.all.first { $0.id == "bundle-reading-nook" }! }
  private var rainy: ShopBundle { ShopBundle.all.first { $0.id == "bundle-rainy-evening" }! }
  private var starter: ShopBundle { ShopBundle.all.first(where: \.isStarter)! }

  private final class Room {
    var style = RoomStyle.standard
    var sent: [(ShopItem.ID, String?)] = []
  }

  private func shop(stamps: Int = 300) -> (ShopStore, ShopCheckout, Room) {
    let store = ShopStore(storage: .memory(), grant: stamps)
    let room = Room()
    let checkout = ShopCheckout(
      store: store, renovator: RoomRenovator(store: store),
      style: { room.style },
      restyle: { room.style = $0 },
      send: { item, note in room.sent.append((item.id, note)) })
    return (store, checkout, room)
  }

  @Test func aBundleIsOneTapForAllOfItAtItsPrice() throws {
    let (store, checkout, _) = shop()
    let items = nook.items(in: catalog)
    guard case .bought(let receipt) = checkout.buy(nook) else {
      Issue.record("not bought")
      return
    }
    #expect(receipt.price == nook.price(of: items))
    #expect(store.stamps == 300 - receipt.price)
    #expect(Set(store.state.layout.placements.map(\.item)) == Set(items.map(\.id)))
    #expect(store.state.hasBought(bundle: nook.id))
  }

  @Test func aBundleWithAViewAndCurtainsDoesUpTheWindow() {
    let (_, checkout, room) = shop()
    guard case .bought = checkout.buy(rainy) else {
      Issue.record("not bought")
      return
    }
    #expect(room.style.curtains == .rose)
    #expect(room.style.view == .mistyLake)
  }

  @Test func undoingABundleTakesAllOfItBack() {
    let (store, checkout, room) = shop()
    guard case .bought(let receipt) = checkout.buy(rainy) else {
      Issue.record("not bought")
      return
    }
    #expect(checkout.undo(receipt))
    #expect(store.stamps == 300)
    #expect(store.state.layout.placements.isEmpty)
    #expect(store.state.closet.counts.isEmpty)
    #expect(room.style == .standard)
    #expect(!store.state.hasBought(bundle: rainy.id))
  }

  @Test func aBundleLeavesOutAndDoesNotChargeForAViewAlreadyOwned() {
    let (_, checkout, _) = shop()
    let view = RoomStyleItem.view(.mistyLake).shopItem!
    guard case .bought = checkout.buy(view) else {
      Issue.record("view not bought")
      return
    }
    let left = checkout.remaining(of: rainy)
    #expect(!left.items.contains(view))
    #expect(left.sum == ShopBundle.sum(of: rainy.items(in: catalog)) - view.price)
    guard case .bought(let receipt) = checkout.buy(rainy) else {
      Issue.record("bundle not bought")
      return
    }
    #expect(receipt.price == left.price)
  }

  @Test func aBundleShortOfStampsSaysHowManyMore() {
    let (store, checkout, _) = shop(stamps: 10)
    let price = checkout.remaining(of: nook).price
    #expect(checkout.buy(nook) == .short(by: price - 10))
    #expect(store.stamps == 10)
    #expect(store.state.layout.placements.isEmpty)
  }

  @Test func aDealIsBoughtAtItsPrice() {
    let (store, checkout, _) = shop()
    let armchair = catalog.item("furniture-armchair")!
    let deal = ShopDeal(item: armchair, price: 22, discount: 25)
    guard case .bought(let receipt) = checkout.buy(deal) else {
      Issue.record("not bought")
      return
    }
    #expect(store.stamps == 278)
    #expect(checkout.undo(receipt))
    #expect(store.stamps == 300)
  }

  @Test func theDailyGiftIsTakenOnceADay() {
    let (store, _, _) = shop(stamps: 0)
    let gift = DailyGift(id: "gift:daily:20396", day: 20_396, reward: .stamps(15))
    #expect(store.claim(gift) == .applied)
    #expect(store.stamps == 15)
    #expect(store.claim(gift) == .duplicate)
    #expect(store.stamps == 15)
    #expect(store.state.hasClaimed(gift))
    let tomorrow = DailyGift(id: "gift:daily:20397", day: 20_397, reward: .item("treat-milk"))
    #expect(!store.state.hasClaimed(tomorrow))
    #expect(store.claim(tomorrow) == .applied)
    #expect(store.owned(catalog.item("treat-milk")!) == 1)
    #expect(store.claim(tomorrow) == .duplicate)
  }

  @Test func aGiftGoesToThePartnerOnlyOnceItCanNoLongerBeUndone() {
    let (store, checkout, room) = shop()
    let mouse = catalog.item("furniture-mouse")!
    guard case .bought(let receipt) = checkout.give(mouse, note: "  for the little one  ") else {
      Issue.record("not bought")
      return
    }
    #expect(store.state.layout.placements.isEmpty)
    #expect(room.sent.isEmpty)
    // Wrapped and about to go: not the room's to place.
    #expect(checkout.owned(mouse) == 0)
    checkout.settle(receipt)
    #expect(room.sent.map(\.0) == [mouse.id])
    #expect(room.sent.map(\.1) == ["for the little one"])
  }

  @Test func anUndoneGiftIsNeverSent() {
    let (store, checkout, room) = shop()
    let mouse = catalog.item("furniture-mouse")!
    guard case .bought(let receipt) = checkout.give(mouse, note: nil) else {
      Issue.record("not bought")
      return
    }
    #expect(checkout.undo(receipt))
    checkout.settle(receipt)
    #expect(room.sent.isEmpty)
    #expect(store.stamps == 300)
  }

  @Test func aGiftStillOpenIsSentWhenTheNextPurchaseIsMade() {
    let (_, checkout, room) = shop()
    let mouse = catalog.item("furniture-mouse")!
    _ = checkout.give(mouse, note: "hi")
    _ = checkout.buy(catalog.item("treat-fish")!)
    #expect(room.sent.map(\.0) == [mouse.id])
  }

  @Test func aViewCannotBeGiven() {
    let (store, checkout, _) = shop()
    #expect(checkout.give(RoomStyleItem.view(.pinkDusk).shopItem!, note: nil) == .refused)
    #expect(store.stamps == 300)
  }

  @Test func aLongNoteIsCut() {
    let (_, checkout, room) = shop()
    let long = String(repeating: "a", count: 200)
    guard case .bought(let receipt) = checkout.give(catalog.item("treat-fish")!, note: long)
    else {
      Issue.record("not bought")
      return
    }
    checkout.settle(receipt)
    #expect(room.sent.first?.1?.count == ShopCheckout.noteLimit)
  }

  @Test func theStarterCountsAsBoughtUntilUndone() {
    let (store, checkout, _) = shop()
    guard case .bought(let receipt) = checkout.buy(starter) else {
      Issue.record("not bought")
      return
    }
    #expect(store.state.hasBought(bundle: starter.id))
    checkout.undo(receipt)
    #expect(!store.state.hasBought(bundle: starter.id))
  }
}
