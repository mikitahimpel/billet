import Foundation
import Testing

@testable import Pet

@Suite("Shop")
struct ShopTests {
  private let catalog = ShopCatalog.standard

  private func item(_ id: String) -> ShopItem { catalog.item(id)! }
  private var armchair: ShopItem { item("furniture-armchair") }
  private var fish: ShopItem { item("treat-fish") }
  private var roseWall: ShopItem { item("wall-rose") }

  private func state(stamps: Int = 100) -> ShopState {
    var shop = ShopState()
    if stamps > 0 { _ = shop.credit(stamps, as: .grant, id: "grant:test") }
    return shop
  }

  @Test func catalogHasUniqueIDsAndThreeSections() {
    let ids = catalog.items.map(\.id)
    #expect(Set(ids).count == ids.count)
    for category in ShopItem.Category.allCases {
      #expect(!catalog.items(in: category).isEmpty)
    }
    #expect(catalog.items.allSatisfy { $0.price > 0 })
  }

  @Test func catalogRoundTripsThroughCodable() throws {
    let data = try JSONEncoder().encode(catalog)
    #expect(try JSONDecoder().decode(ShopCatalog.self, from: data) == catalog)
  }

  @Test func cannotOverspend() {
    var shop = state(stamps: armchair.price - 1)
    #expect(throws: ShopError.notEnoughStamps(needed: armchair.price, have: armchair.price - 1)) {
      try shop.buy(armchair, transaction: "t1")
    }
    #expect(shop.wallet.balance == armchair.price - 1)
    #expect(shop.closet.isEmpty)
    // The failed buy did not use up its ID: the same tap can succeed once stamps arrive.
    #expect(!shop.hasApplied("t1"))
  }

  @Test func exactBalanceBuysAndEmptiesTheWallet() throws {
    var shop = state(stamps: fish.price)
    #expect(try shop.buy(fish, transaction: "t1") == .applied)
    #expect(shop.wallet.balance == 0)
  }

  @Test func boughtItemGoesToTheCloset() throws {
    var shop = state()
    _ = try shop.buy(armchair, transaction: "t1")
    #expect(shop.closet.count(of: armchair.id) == 1)
    #expect(shop.wallet.balance == 100 - armchair.price)
  }

  @Test func theSameBuyCannotApplyTwice() throws {
    var shop = state()
    #expect(try shop.buy(armchair, transaction: "t1") == .applied)
    #expect(try shop.buy(armchair, transaction: "t1") == .duplicate)
    #expect(shop.closet.count(of: armchair.id) == 1)
    #expect(shop.wallet.balance == 100 - armchair.price)
  }

  @Test func aDuplicateBuyIsIgnoredEvenWhenItCouldNoLongerBePaid() throws {
    var shop = state(stamps: armchair.price)
    _ = try shop.buy(armchair, transaction: "t1")
    #expect(try shop.buy(armchair, transaction: "t1") == .duplicate)
  }

  @Test func aMaterialIsBoughtOnce() throws {
    var shop = state()
    _ = try shop.buy(roseWall, transaction: "t1")
    #expect(throws: ShopError.alreadyOwned) { try shop.buy(roseWall, transaction: "t2") }
    #expect(shop.wallet.balance == 100 - roseWall.price)
  }

  @Test func furnitureCanBeBoughtAgain() throws {
    var shop = state()
    _ = try shop.buy(armchair, transaction: "t1")
    _ = try shop.buy(armchair, transaction: "t2")
    #expect(shop.closet.count(of: armchair.id) == 2)
  }

  @Test func aConsumableIsUsedUp() throws {
    var shop = state()
    _ = try shop.buy(fish, transaction: "b1")
    _ = try shop.buy(fish, transaction: "b2")
    #expect(try shop.use(fish, transaction: "u1") == .applied)
    #expect(shop.closet.count(of: fish.id) == 1)
    #expect(shop.treatsUsed == 1)
    #expect(shop.lastTreat == fish.id)
    _ = try shop.use(fish, transaction: "u2")
    #expect(shop.closet.isEmpty)
    #expect(throws: ShopError.notInCloset) { try shop.use(fish, transaction: "u3") }
    #expect(shop.treatsUsed == 2)
  }

  @Test func aTreatUsedTwiceUnderOneIDIsUsedOnce() throws {
    var shop = state()
    _ = try shop.buy(fish, transaction: "b1")
    _ = try shop.buy(fish, transaction: "b2")
    _ = try shop.use(fish, transaction: "u1")
    #expect(try shop.use(fish, transaction: "u1") == .duplicate)
    #expect(shop.closet.count(of: fish.id) == 1)
  }

  @Test func furnitureCannotBeUsedAndTreatsCannotBePlaced() throws {
    var shop = state()
    _ = try shop.buy(armchair, transaction: "b1")
    _ = try shop.buy(fish, transaction: "b2")
    #expect(throws: ShopError.wrongKind) { try shop.use(armchair, transaction: "u1") }
    #expect(throws: ShopError.wrongKind) { try shop.place(fish, transaction: "p1") }
  }

  @Test func placedFurnitureLeavesTheCloset() throws {
    var shop = state()
    _ = try shop.buy(armchair, transaction: "b1")
    #expect(try shop.place(armchair, transaction: "p1") == .applied)
    #expect(shop.closet.count(of: armchair.id) == 0)
    #expect(shop.layout.placements.map(\.item) == [armchair.id])
  }

  @Test func furnitureNotInTheClosetCannotBePlaced() {
    var shop = state()
    #expect(throws: ShopError.notInCloset) { try shop.place(armchair, transaction: "p1") }
    #expect(shop.layout.placements.isEmpty)
  }

  @Test func removedFurnitureReturnsToTheCloset() throws {
    var shop = state()
    _ = try shop.buy(armchair, transaction: "b1")
    _ = try shop.place(armchair, transaction: "p1")
    let placed = try #require(shop.layout.placements.first)
    #expect(try shop.remove(placement: placed.id, transaction: "r1") == .applied)
    #expect(shop.closet.count(of: armchair.id) == 1)
    #expect(shop.layout.placements.isEmpty)
    #expect(try shop.remove(placement: placed.id, transaction: "r1") == .duplicate)
    #expect(shop.closet.count(of: armchair.id) == 1)
    #expect(throws: ShopError.unknownPlacement) {
      try shop.remove(placement: placed.id, transaction: "r2")
    }
  }

  @Test func everyCopyIsAccountedForAfterPlacingAndRemoving() throws {
    var shop = state()
    _ = try shop.buy(armchair, transaction: "b1")
    _ = try shop.buy(armchair, transaction: "b2")
    _ = try shop.place(armchair, transaction: "p1")
    _ = try shop.place(armchair, transaction: "p2")
    #expect(shop.closet.count(of: armchair.id) == 0)
    #expect(shop.layout.placements.count == 2)
    _ = try shop.remove(placement: "placed-p1", transaction: "r1")
    #expect(shop.closet.count(of: armchair.id) + shop.layout.placements.count == 2)
  }

  @Test func piecesTakeDifferentSpotsAndTheRoomFills() throws {
    var shop = state(stamps: 1000)
    for index in 0..<RoomLayout.floorSpots.count {
      _ = try shop.buy(armchair, transaction: "b\(index)")
      _ = try shop.place(armchair, transaction: "p\(index)")
    }
    let spots = Set(shop.layout.placements.map { "\($0.x),\($0.z)" })
    #expect(spots.count == RoomLayout.floorSpots.count)
    _ = try shop.buy(armchair, transaction: "bx")
    #expect(throws: ShopError.roomIsFull) { try shop.place(armchair, transaction: "px") }
    #expect(shop.closet.count(of: armchair.id) == 1)
  }

  @Test func aMaterialIsPaintedAndStaysOwned() throws {
    var shop = state()
    _ = try shop.buy(roseWall, transaction: "b1")
    #expect(try shop.paint(roseWall, transaction: "c1") == .applied)
    #expect(shop.layout.wall == roseWall.id)
    #expect(shop.layout.floor == nil)
    #expect(shop.closet.count(of: roseWall.id) == 1)
    let sage = item("wall-sage")
    _ = try shop.buy(sage, transaction: "b2")
    _ = try shop.paint(sage, transaction: "c2")
    #expect(shop.layout.wall == sage.id)
  }

  @Test func anUnownedMaterialCannotBePainted() {
    var shop = state()
    #expect(throws: ShopError.notInCloset) { try shop.paint(roseWall, transaction: "c1") }
    #expect(shop.layout.wall == nil)
  }

  // MARK: Ledger

  @Test func balanceIsTheSumOfLedgerEntries() throws {
    var shop = state(stamps: 50)
    #expect(shop.credit(25, as: .purchase, id: "purchase:a") == .applied)
    _ = try shop.buy(fish, transaction: "b1")
    let entries = shop.wallet.entries
    #expect(entries.map(\.source) == [.grant, .purchase, .spend])
    #expect(entries.map(\.amount) == [50, 25, -fish.price])
    #expect(shop.wallet.balance == entries.reduce(0) { $0 + $1.amount })
    #expect(Set(entries.map(\.id)).count == entries.count)
  }

  @Test func aPurchaseOfStampsCannotApplyTwice() {
    var shop = state(stamps: 0)
    #expect(shop.credit(500, as: .purchase, id: "purchase:abc") == .applied)
    #expect(shop.credit(500, as: .purchase, id: "purchase:abc") == .duplicate)
    #expect(shop.wallet.balance == 500)
    #expect(shop.wallet.entries.count == 1)
  }

  @Test func aCreditIDCannotBeReusedForAnotherSource() {
    var shop = state(stamps: 0)
    _ = shop.credit(10, as: .grant, id: "x")
    #expect(shop.credit(10, as: .purchase, id: "x") == .duplicate)
    #expect(shop.wallet.balance == 10)
  }

  @Test func nothingNonPositiveIsCredited() {
    var shop = state(stamps: 0)
    #expect(shop.credit(0, as: .grant, id: "z") == .duplicate)
    #expect(shop.credit(-5, as: .grant, id: "n") == .duplicate)
    #expect(shop.wallet.entries.isEmpty)
  }

  @Test func aFailedSpendWritesNoEntry() {
    var shop = state(stamps: 1)
    #expect(throws: ShopError.self) { try shop.buy(armchair, transaction: "b1") }
    #expect(shop.wallet.entries.count == 1)
  }

  // MARK: Store

  @MainActor private func store(_ storage: ShopStorage = .memory(), grant: Int = 1000) -> ShopStore
  {
    ShopStore(storage: storage, grant: grant)
  }

  @Test func demoGrantIsOneNamedValue() {
    #expect(ShopConfig.demoGrant == 10_000)
  }

  @MainActor @Test func theIdolPiecesAreForSaleOnlyWhileTheirLabIsOn() throws {
    let shop = store()
    let standard = shop.catalog.items.map(\.id)
    #expect(!standard.contains { $0.hasPrefix("furniture-idol-") })
    shop.showsIdolProps = true
    let idol = shop.catalog.items(in: .furniture).filter { $0.id.hasPrefix("furniture-idol-") }
    #expect(idol.count == 11)
    // Beside the hand-made pieces, none of them taken away.
    #expect(Set(standard).isSubset(of: Set(shop.catalog.items.map(\.id))))
    for item in idol {
      guard case .furniture(let model, _, let size, .floor) = item.look else {
        Issue.record("\(item.id) is not floor furniture")
        continue
      }
      #expect(model.hasPrefix("Idol_"))
      #expect(size > 0)
    }
    let bed = try #require(shop.catalog.item("furniture-idol-catbed"))
    try shop.buy(bed, transaction: "idol-1")
    #expect(shop.owned(bed) == 1)
    shop.showsIdolProps = false
    #expect(shop.catalog.item(bed.id) == nil)
  }

  @MainActor @Test func aNewShopIsGrantedTheDemoAmountByDefault() {
    #expect(ShopStore(storage: .memory()).stamps == ShopConfig.demoGrant)
  }

  @MainActor @Test func theGrantAppliesOnceAcrossLaunches() throws {
    let storage = ShopStorage.memory()
    let first = store(storage)
    #expect(first.stamps == 1000)
    try first.buy(fish, transaction: "b1")
    let again = store(storage)
    let third = store(storage)
    #expect(again.stamps == 1000 - fish.price)
    #expect(third.state.wallet.entries.filter { $0.source == .grant }.count == 1)
    #expect(third.state.wallet.entries.first?.id == ShopStore.grantID)
  }

  @MainActor @Test func theStoreSavesAfterEachChangeAndReloads() throws {
    let storage = ShopStorage.memory()
    let shop = store(storage)
    try shop.buy(armchair, transaction: "b1")
    try shop.place(armchair, transaction: "p1")
    let reopened = store(storage)
    #expect(reopened.state == shop.state)
    #expect(reopened.stamps == 1000 - armchair.price)
  }

  @MainActor @Test func aReplayedTransactionAfterReopeningStillCountsOnce() throws {
    let storage = ShopStorage.memory()
    try store(storage).buy(armchair, transaction: "b1")
    let reopened = store(storage)
    #expect(try reopened.buy(armchair, transaction: "b1") == .duplicate)
    #expect(reopened.owned(armchair) == 1)
    #expect(reopened.stamps == 1000 - armchair.price)
  }

  @MainActor @Test func aFailedChangeLeavesTheStoreUntouched() {
    let shop = store()
    let before = shop.state
    #expect(throws: ShopError.notInCloset) { try shop.place(armchair, transaction: "p1") }
    #expect(shop.state == before)
  }
}
