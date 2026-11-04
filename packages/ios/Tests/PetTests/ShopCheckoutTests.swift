import Foundation
import Testing

@testable import Pet

/// One tap to buy, a few seconds to take it back, and a clear answer when stamps run short.
@MainActor
@Suite("Shop checkout")
struct ShopCheckoutTests {
  private let catalog = ShopCatalog.standard
  private var armchair: ShopItem { catalog.item("furniture-armchair")! }
  private var framedPrint: ShopItem { catalog.item("furniture-print")! }
  private var fish: ShopItem { catalog.item("treat-fish")! }
  private var pinkDusk: ShopItem { RoomStyleItem.view(.pinkDusk).shopItem! }

  private final class Room {
    var style = RoomStyle.standard
    var shared: [RoomStyle] = []
  }

  private func shop(stamps: Int = 100, state: ShopState? = nil) -> (ShopStore, ShopCheckout, Room) {
    let store = ShopStore(storage: .memory(state), grant: stamps)
    let room = Room()
    let checkout = ShopCheckout(
      store: store, renovator: RoomRenovator(store: store),
      style: { room.style },
      restyle: { style in
        room.style = style
        room.shared.append(style)
      })
    return (store, checkout, room)
  }

  // MARK: buying

  @Test func oneTapPaysAndStandsThePieceInTheRoom() throws {
    let (store, checkout, _) = shop()
    guard case .bought(let receipt) = checkout.buy(armchair) else {
      Issue.record("not bought")
      return
    }
    #expect(store.stamps == 100 - armchair.price)
    let placement = try #require(receipt.placement)
    #expect(store.state.layout.placements.map(\.id) == [placement])
    #expect(store.state.layout.placements.first?.item == armchair.id)
    #expect(store.owned(armchair) == 0)
    #expect(!receipt.needsPlacing)
    #expect(checkout.latest == receipt)
  }

  @Test func aWallPieceGoesOnTheWall() throws {
    let (store, checkout, _) = shop()
    guard case .bought = checkout.buy(framedPrint) else {
      Issue.record("not bought")
      return
    }
    let placed = try #require(store.state.layout.placements.first)
    #expect(placed.z == RoomLayout.wallSpots[0].z)
  }

  @Test func aPieceWaitsInTheClosetWhenTheRoomIsFull() {
    let (store, checkout, _) = shop(stamps: 1_000)
    for _ in RoomLayout.floorSpots { _ = checkout.buy(armchair) }
    guard case .bought(let receipt) = checkout.buy(armchair) else {
      Issue.record("not bought")
      return
    }
    #expect(receipt.placement == nil)
    #expect(receipt.needsPlacing)
    #expect(store.owned(armchair) == 1)
    #expect(store.state.layout.placements.count == RoomLayout.floorSpots.count)
  }

  @Test func aTreatGoesToTheCloset() {
    let (store, checkout, _) = shop()
    guard case .bought(let receipt) = checkout.buy(fish) else {
      Issue.record("not bought")
      return
    }
    #expect(store.owned(fish) == 1)
    #expect(!receipt.needsPlacing)
    #expect(store.state.layout.placements.isEmpty)
  }

  @Test func aViewIsUnlockedAndShownInTheWindow() {
    let (store, checkout, room) = shop()
    guard case .bought = checkout.buy(pinkDusk) else {
      Issue.record("not bought")
      return
    }
    #expect(room.style.view == .pinkDusk)
    #expect(store.state.owns(pinkDusk))
    #expect(checkout.isOwned(pinkDusk))
    #expect(checkout.buy(pinkDusk) == .owned)
    #expect(store.stamps == 100 - pinkDusk.price)
  }

  @Test func anOwnedViewIsUsedWithoutPaying() {
    let (store, checkout, room) = shop()
    _ = checkout.buy(pinkDusk)
    room.style = .standard
    checkout.use(.view(.pinkDusk))
    #expect(room.style.view == .pinkDusk)
    #expect(store.stamps == 100 - pinkDusk.price)
  }

  @Test func aLockedViewIsNotUsedForFree() {
    let (_, checkout, room) = shop()
    checkout.use(.view(.pinkDusk))
    #expect(room.style == .standard)
    #expect(room.shared.isEmpty)
  }

  // MARK: undo

  @Test func undoGivesTheStampsBackAndTakesThePieceOut() throws {
    let (store, checkout, _) = shop()
    guard case .bought(let receipt) = checkout.buy(armchair) else {
      Issue.record("not bought")
      return
    }
    #expect(checkout.undo(receipt))
    #expect(store.stamps == 100)
    #expect(store.state.layout.placements.isEmpty)
    #expect(store.owned(armchair) == 0)
    #expect(checkout.latest == nil)
    #expect(store.state.wallet.entries.last?.source == .refund)
  }

  @Test func undoAPieceThatWaitedInTheCloset() {
    let (store, checkout, _) = shop(stamps: 1_000)
    for _ in RoomLayout.floorSpots { _ = checkout.buy(armchair) }
    guard case .bought(let receipt) = checkout.buy(armchair) else {
      Issue.record("not bought")
      return
    }
    let before = store.stamps
    #expect(checkout.undo(receipt))
    #expect(store.stamps == before + armchair.price)
    #expect(store.owned(armchair) == 0)
    #expect(store.state.layout.placements.count == RoomLayout.floorSpots.count)
  }

  @Test func undoPutsTheWindowBack() {
    let (store, checkout, room) = shop()
    room.style = RoomStyle(view: .rainySuburb)
    guard case .bought(let receipt) = checkout.buy(pinkDusk) else {
      Issue.record("not bought")
      return
    }
    #expect(checkout.undo(receipt))
    #expect(room.style.view == .rainySuburb)
    #expect(!store.state.owns(pinkDusk))
    #expect(store.stamps == 100)
  }

  @Test func undoWorksOnceAndOnlyForTheLatest() {
    let (store, checkout, _) = shop()
    guard case .bought(let first) = checkout.buy(fish),
      case .bought(let second) = checkout.buy(fish)
    else {
      Issue.record("not bought")
      return
    }
    #expect(!checkout.undo(first))
    #expect(checkout.undo(second))
    #expect(!checkout.undo(second))
    #expect(store.owned(fish) == 1)
    #expect(store.stamps == 100 - fish.price)
  }

  @Test func aSettledPurchaseCannotBeUndone() {
    let (store, checkout, _) = shop()
    guard case .bought(let receipt) = checkout.buy(armchair) else {
      Issue.record("not bought")
      return
    }
    checkout.settle(receipt)
    #expect(!checkout.undo(receipt))
    #expect(store.stamps == 100 - armchair.price)
  }

  @Test func aTreatAlreadyGivenCannotBeUndone() {
    let (store, checkout, _) = shop()
    guard case .bought(let receipt) = checkout.buy(fish) else {
      Issue.record("not bought")
      return
    }
    _ = try? store.use(fish, transaction: "eat")
    #expect(!checkout.undo(receipt))
    #expect(store.stamps == 100 - fish.price)
  }

  @Test func anUndoneBuySurvivesARelaunch() {
    let storage = ShopStorage.memory()
    let store = ShopStore(storage: storage, grant: 100)
    let checkout = ShopCheckout(store: store, renovator: RoomRenovator(store: store))
    guard case .bought(let receipt) = checkout.buy(armchair) else {
      Issue.record("not bought")
      return
    }
    checkout.undo(receipt)
    let relaunched = ShopStore(storage: storage, grant: 100)
    #expect(relaunched.stamps == 100)
    #expect(relaunched.state.layout.placements.isEmpty)
  }

  // MARK: not enough stamps

  @Test func shortOfStampsSaysHowManyMoreAndChangesNothing() {
    let (store, checkout, room) = shop(stamps: 5)
    #expect(checkout.shortfall(for: armchair) == armchair.price - 5)
    #expect(checkout.buy(armchair) == .short(by: armchair.price - 5))
    #expect(store.stamps == 5)
    #expect(store.state.layout.placements.isEmpty)
    #expect(checkout.latest == nil)
    #expect(checkout.buy(pinkDusk) == .short(by: pinkDusk.price - store.stamps))
    #expect(room.shared.isEmpty)
  }

  @Test func enoughStampsHasNoShortfall() {
    let (_, checkout, _) = shop(stamps: armchair.price)
    #expect(checkout.shortfall(for: armchair) == 0)
    guard case .bought = checkout.buy(armchair) else {
      Issue.record("not bought")
      return
    }
    #expect(checkout.shortfall(for: armchair) == armchair.price)
  }
}

@Suite("Shop shelves")
struct ShopShelfTests {
  @Test func everyShelfHasSomethingAndNoItemIsOnTwo() {
    let catalog = ShopCatalog.standard.withIdolProps
    var seen: Set<ShopItem.ID> = []
    for shelf in ShopItem.Shelf.allCases {
      let items = catalog.items(on: shelf)
      #expect(!items.isEmpty, "\(shelf)")
      for item in items { #expect(seen.insert(item.id).inserted, "\(item.id)") }
    }
  }

  @Test func idolPropsShowOnlyWithTheirFlag() {
    let plain = ShopCatalog.standard.items(on: .decor).map(\.id)
    let pilot = ShopCatalog.standard.withIdolProps.items(on: .decor).map(\.id)
    #expect(!plain.contains { $0.hasPrefix("furniture-idol-") })
    #expect(pilot.contains("furniture-idol-lavalamp"))
  }

  @Test func onlyPaidViewsAreSold() {
    let views = ShopCatalog.standard.items(on: .views)
    #expect(views.allSatisfy { $0.price > 0 })
    #expect(views.contains { $0.id == RoomStyleItem.view(.pinkDusk).shopID })
    #expect(!views.contains { $0.id == RoomStyleItem.view(.suburbNight).shopID })
  }

  @Test func paintsAndOtherStylesStayInTheStyleTab() {
    #expect(ShopCatalog.standard.item("wall-rose")?.shelf == nil)
    #expect(RoomStyleItem.wall(.teal).shopItem?.shelf == nil)
  }

  @Test func catThingsAreTogether() {
    let cat = ShopCatalog.standard.withIdolProps.items(on: .cat).map(\.id)
    for id in ["treat-fish", "furniture-tower", "furniture-mouse", "furniture-idol-scratchpost"] {
      #expect(cat.contains(id), "\(id)")
    }
  }
}

@Suite("Shop undo in the ledger")
struct ShopUndoStateTests {
  @Test func anUnknownPurchaseCannotBeUndone() {
    var state = ShopState()
    _ = state.credit(50, as: .grant, id: "g")
    let fish = ShopCatalog.standard.item("treat-fish")!
    #expect(throws: ShopError.unknownPurchase) {
      try state.undoBuy(fish, transaction: "never")
    }
    #expect(state.wallet.balance == 50)
  }

  @Test func undoingTwiceRefundsOnce() throws {
    var state = ShopState()
    _ = state.credit(50, as: .grant, id: "g")
    let fish = ShopCatalog.standard.item("treat-fish")!
    _ = try state.buy(fish, transaction: "t")
    _ = try state.buy(fish, transaction: "u")
    #expect(try state.undoBuy(fish, transaction: "t") == .applied)
    #expect(try state.undoBuy(fish, transaction: "t") == .duplicate)
    #expect(state.wallet.balance == 50 - fish.price)
    #expect(state.closet.count(of: fish.id) == 1)
  }

  /// A wallet saved before refunds existed still decodes, and one with a refund round-trips.
  @Test func aWalletWithARefundRoundTrips() throws {
    var state = ShopState()
    _ = state.credit(50, as: .grant, id: "g")
    let fish = ShopCatalog.standard.item("treat-fish")!
    _ = try state.buy(fish, transaction: "t")
    _ = try state.undoBuy(fish, transaction: "t")
    let data = try JSONEncoder().encode(state)
    #expect(try JSONDecoder().decode(ShopState.self, from: data) == state)
  }
}
