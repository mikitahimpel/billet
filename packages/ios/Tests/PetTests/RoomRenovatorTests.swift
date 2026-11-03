import Testing

@testable import Pet

@MainActor
@Suite struct RoomRenovatorTests {
  private let shop = ShopStore(storage: .memory())
  private var catalog: ShopCatalog { shop.catalog }

  private func owned(_ pick: (ShopItem) -> Bool) throws -> ShopItem {
    let match = catalog.items.first(where: pick)
    let item = try #require(match)
    try shop.buy(item, transaction: shop.newTransaction())
    return item
  }

  private func floorPiece() throws -> ShopItem {
    try owned {
      if case .furniture(_, _, _, .floor) = $0.look { true } else { false }
    }
  }

  private func wallPiece() throws -> ShopItem {
    try owned {
      if case .furniture(_, _, _, .wall) = $0.look { true } else { false }
    }
  }

  private func wallPaint() throws -> ShopItem {
    try owned {
      if case .material(.wall, _) = $0.look { true } else { false }
    }
  }

  @Test func aFloorPieceGoesWhereTheScenesPlanHasRoom() throws {
    let renovator = RoomRenovator(store: shop)
    renovator.openSpot = { _ in (x: 0.3, z: -0.4) }
    try renovator.renovate(.place(floorPiece()))
    let placed = try #require(shop.state.layout.placements.first)
    #expect(placed.x == 0.3)
    #expect(placed.z == -0.4)
    #expect(renovator.placements == 1)
  }

  @Test func aSceneWithNoRoomLeftRefusesThePiece() throws {
    let renovator = RoomRenovator(store: shop)
    renovator.openSpot = { _ in nil }
    let item = try floorPiece()
    #expect(throws: ShopError.roomIsFull) { try renovator.renovate(.place(item)) }
    #expect(shop.owned(item) == 1)
    #expect(renovator.placements == 0)
  }

  @Test func withoutAScenePlanTheStorePicksTheSpot() throws {
    let renovator = RoomRenovator(store: shop)
    try renovator.renovate(.place(floorPiece()))
    #expect(shop.state.layout.placements.count == 1)
  }

  @Test func aWallPieceDoesNotAskTheFloorPlan() throws {
    let renovator = RoomRenovator(store: shop)
    renovator.openSpot = { _ in nil }
    try renovator.renovate(.place(wallPiece()))
    #expect(shop.state.layout.placements.count == 1)
  }

  @Test func movingKeepsTheWayAPieceFaces() throws {
    let renovator = RoomRenovator(store: shop)
    try renovator.renovate(.place(floorPiece()))
    let placed = try #require(shop.state.layout.placements.first)
    try shop.move(placement: placed.id, x: placed.x, z: placed.z, yaw: 1.5)
    renovator.moved(placement: placed.id, x: 0.1, z: 0.2)
    let moved = try #require(shop.state.layout.placements.first)
    #expect(moved.x == 0.1)
    #expect(moved.z == 0.2)
    #expect(moved.yaw == 1.5)
  }

  @Test func aPieceAlreadyPutAwayCannotBeMoved() {
    let renovator = RoomRenovator(store: shop)
    renovator.moved(placement: "gone", x: 0, z: 0)
    #expect(shop.state.layout.placements.isEmpty)
  }

  @Test func puttingAwayReturnsThePieceToTheCloset() throws {
    let renovator = RoomRenovator(store: shop)
    let item = try floorPiece()
    try renovator.renovate(.place(item))
    let placed = try #require(shop.state.layout.placements.first)
    try renovator.renovate(.putAway(placement: placed.id))
    #expect(shop.state.layout.placements.isEmpty)
    #expect(shop.owned(item) == 1)
  }

  @Test func clearingASurfaceKeepsTheMaterialOwned() throws {
    let renovator = RoomRenovator(store: shop)
    let paint = try wallPaint()
    try renovator.renovate(.paint(paint))
    #expect(shop.state.layout.wall == paint.id)
    renovator.cleared(.wall)
    #expect(shop.state.layout.wall == nil)
    #expect(shop.state.owns(paint))
  }

  // MARK: - Decorating in place

  @Test func aPieceFromTheClosetStandsWhereItIsPutAndTurned() throws {
    let renovator = RoomRenovator(store: shop)
    let item = try floorPiece()
    let id = try renovator.place(item, at: (x: 0.2, z: 0.1), yaw: 1.5)
    let placed = try #require(renovator.placement(id))
    #expect(placed.x == 0.2 && placed.z == 0.1 && placed.yaw == 1.5)
    #expect(renovator.owned(item) == 0)
    #expect(!renovator.closetFurniture.contains(item))
  }

  @Test func putAwayGoesBackToTheCloset() throws {
    let renovator = RoomRenovator(store: shop)
    let item = try floorPiece()
    let id = try renovator.place(item, at: (x: 0, z: 0))
    try renovator.putAway(id)
    #expect(renovator.placement(id) == nil)
    #expect(renovator.owned(item) == 1)
    #expect(renovator.closetFurniture.contains(item))
  }

  @Test func aMoveKeepsTheTurnUnlessGivenANewOne() throws {
    let renovator = RoomRenovator(store: shop)
    let id = try renovator.place(floorPiece(), at: (x: 0, z: 0), yaw: 0.5)
    renovator.moved(placement: id, x: 0.3, z: -0.2)
    #expect(renovator.placement(id)?.yaw == 0.5)
    renovator.moved(placement: id, x: 0.3, z: -0.2, yaw: -1)
    let placed = try #require(renovator.placement(id))
    #expect(placed.x == 0.3 && placed.z == -0.2 && placed.yaw == -1)
  }
}
