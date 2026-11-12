import Foundation
import Testing

@testable import DecorInterface

@Suite struct DecorBedroomTests {
  private let fresh = DecorLayout()
  private let bedroom = DecorRoom.bedroom

  private func at(_ id: String, _ u: Int, _ v: Int, _ turns: Int = 0, space: DecorSpace = .bedroom)
    -> Placement
  {
    Placement(item: id, surface: .floor, u: u, v: v, quarterTurns: turns, space: space)
  }

  @Test func theBedroomHasItsOwnFurnitureAndTheLivingRoomKeepsItsOwn() {
    #expect(DecorItem.baseItems(in: .bedroom).count == 9)
    #expect(DecorItem.baseItems(in: .living).count == 10)
    #expect(fresh.allPlacements(in: bedroom).count == 9)
    #expect(fresh.allPlacements(in: .home).count == 10)
    #expect(DecorItem.baseItems(in: .bedroom).allSatisfy { $0.id.hasPrefix("base-bedroom-") })
    #expect(fresh.allPlacements(in: bedroom).allSatisfy { $0.space == .bedroom })
  }

  /// CityRoomScene's furniture as `CityLayout` has it (middle x, z in metres): the default room is where the
  /// Bedroom always stood, within a cell.
  @Test func theDefaultBedroomIsTodaysPositionsWithinACell() {
    let built: [(String, Double, Double)] = [
      ("base-bedroom-bed", 0.06, -0.17), ("base-bedroom-nightstand", -0.415, -0.17),
      ("base-bedroom-dresser", -0.44, 0.28), ("base-bedroom-catbed", 0.28, 0.27),
      ("base-bedroom-rug", 0.04, 0.24),
    ]
    for (id, x, z) in built {
      let spot = fresh.placement(of: id)!
      #expect(abs(DecorGrid.metres(spot.u) - x) <= DecorGrid.step, "\(id) x")
      #expect(abs(DecorGrid.metres(spot.v) - z) <= DecorGrid.step, "\(id) z")
    }
  }

  @Test func everyDefaultFitsAndLeavesHerEnoughFloor() {
    for placement in fresh.allPlacements(in: bedroom) {
      #expect(fresh.verdict(placement, in: bedroom) == .fits, "\(placement.item)")
    }
    #expect(fresh.occupancy(in: bedroom).bareShare >= bedroom.minimumFree)
  }

  @Test func aPieceOfOneRoomDoesNotFitTheOther() {
    #expect(fresh.verdict(at("base-bedroom-bed", 1, -3), in: .home) == .wrongSurface)
    #expect(fresh.verdict(at("base-plant", -8, -8, space: .living), in: bedroom) == .wrongSurface)
    #expect(
      fresh.verdict(at("base-bedroom-bed", 1, -3, space: .living), in: .home) == .wrongSurface)
  }

  @Test func theTwoRoomsKeepApartWhatStandsInThem() {
    // Where the bedroom's bed is, the living room has floor; the living room's pieces do not block the bedroom.
    let lamp = at("lamp", 1, -3, space: .living)
    let layout = fresh.putting(at("base-donutbed", -6, 4, space: .living))
    #expect(
      layout.verdict(lamp, in: .home) == .fits || layout.verdict(lamp, in: .home) == .occupied)
    #expect(fresh.occupancy(in: bedroom) != fresh.occupancy(in: .home))
    let moved = fresh.putting(at("base-bedroom-bed", 2, -3))
    #expect(moved.allPlacements(in: .home) == fresh.allPlacements(in: .home))
    #expect(moved.placement(of: "base-bedroom-bed")?.u == 2)
  }

  @Test func aBoughtPieceMovesFromOneRoomToTheOther() {
    let owned: Set<String> = ["armchair"]
    let living = DecorLayout(placements: [at("armchair", -2, 6, space: .living)], stored: [])
    let there = living.putting(at("armchair", -5, 6))
    #expect(there.placement(of: "armchair")?.space == .bedroom)
    #expect(there.allPlacements(in: .home).contains { $0.item == "armchair" } == false)
    #expect(there.closet(owned: owned, in: bedroom).contains { $0.id == "armchair" } == false)
  }

  @Test func eachRoomKeepsABedForHer() {
    #expect(fresh.canStore("base-bedroom-bed") && fresh.canStore("base-bedroom-catbed"))
    let one = fresh.storing("base-bedroom-catbed")
    #expect(!one.canStore("base-bedroom-bed"))
    // The living room's bed does not count for the bedroom, nor the other way round.
    #expect(fresh.canStore("base-donutbed") == false)
    #expect(fresh.storing("base-bedroom-catbed").canStore("base-donutbed") == false)
  }

  @Test func theClosetShowsTheRoomsOwnStowedPieces() {
    let layout = fresh.storing("base-bedroom-slippers").storing("base-plant")
    #expect(layout.closet(owned: [], in: bedroom).map(\.id) == ["base-bedroom-slippers"])
    #expect(layout.closet(owned: [], in: .home).map(\.id) == ["base-plant"])
  }

  @Test func resettingOneRoomLeavesTheOther() {
    let arranged = fresh.putting(at("base-bedroom-bed", 3, -3)).putting(
      at("base-cattree", 7, 0, space: .living)
    ).storing("base-bedroom-mouse")
    let bedroomReset = arranged.reset(owned: [], in: bedroom)
    #expect(bedroomReset.allPlacements(in: bedroom) == fresh.allPlacements(in: bedroom))
    #expect(bedroomReset.placement(of: "base-cattree")?.u == 7)
    let livingReset = arranged.reset(owned: [], in: .home)
    #expect(livingReset.allPlacements(in: .home) == fresh.allPlacements(in: .home))
    #expect(livingReset.placement(of: "base-bedroom-bed")?.u == 3)
    #expect(livingReset.placement(of: "base-bedroom-mouse") == nil)
  }

  @Test func aNewBoughtPieceGoesIntoTheLivingRoomNotTheBedroom() {
    let settled = DecorLayout(stored: []).settled(owned: ["yarn"], in: bedroom)
    #expect(!settled.isPlaced("yarn"))
    let living = DecorLayout(stored: []).settled(owned: ["yarn"])
    #expect(living.placement(of: "yarn")?.space == .living)
  }

  @Test func sheStepsDownFromHerBedAndTheCatSpotsFollowTheLayout() {
    let spawn = fresh.spawn(in: bedroom)
    #expect(abs(spawn.x - 0.13) < 0.001 && abs(spawn.z - 0.13) < 0.001)
    let moved = fresh.putting(at("base-bedroom-catbed", -3, 6))
    let after = moved.spawn(in: bedroom)
    #expect(abs(after.x - (-0.15 - 0.12)) < 0.001 && abs(after.z - (0.30 - 0.17)) < 0.001)

    let withPost = fresh.storing("base-bedroom-slippers").putting(at("scratchpost", -5, 1))
    let plans = withPost.catSpots(in: bedroom)
    #expect(plans.map(\.use) == [.post])
    #expect(plans.first?.item == "scratchpost")
    #expect(withPost.catSpots(in: .home).isEmpty)
    #expect(fresh.canVisit("bed", in: bedroom))
    #expect(!fresh.storing("base-bedroom-bed").canVisit("bed", in: bedroom))
  }

  @Test func aPlacementCarriesItsRoomOnTheWireOnlyInTheBedroom() throws {
    let living = try JSONEncoder().encode(at("armchair", 1, 1, space: .living))
    #expect(!String(decoding: living, as: UTF8.self).contains("room"))
    let there = at("armchair", 1, 1)
    let back = try JSONDecoder().decode(Placement.self, from: JSONEncoder().encode(there))
    #expect(back == there)
    let old = Data(#"{"item":"armchair","surface":"floor","u":1,"v":1,"quarterTurns":0}"#.utf8)
    #expect(try JSONDecoder().decode(Placement.self, from: old).space == .living)
  }
}
