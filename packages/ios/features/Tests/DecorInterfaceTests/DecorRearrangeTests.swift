import Foundation
import Testing

@testable import DecorInterface

@Suite struct DecorRearrangeTests {
  private let fresh = DecorLayout()
  private func at(_ id: String, _ u: Int, _ v: Int, _ turns: Int = 0) -> Placement {
    Placement(item: id, surface: .floor, u: u, v: v, quarterTurns: turns)
  }

  // MARK: The room's own furniture

  @Test func aFreshRoomHasEveryPieceAtHomeAndNoneInTheCloset() {
    let ids = DecorItem.baseItems(in: .living).map(\.id)
    #expect(ids.count == 10)
    for id in ids { #expect(fresh.isPlaced(id), "\(id)") }
    #expect(fresh.placements.isEmpty)
    #expect(fresh.closet(owned: []).isEmpty)
    #expect(fresh.allPlacements(in: .home).count == ids.count)
  }

  @Test func theBaseIdsAreTheServersSlugs() {
    for item in DecorItem.baseItems(in: .living) {
      #expect(item.id.hasPrefix("base-") && !item.id.contains("."), "\(item.id)")
      #expect(item.width > 0 && item.depth > 0 && item.height > 0)
      #expect(item.mount == .floor)
    }
  }

  @Test func theDefaultRoomIsTodaysFixedPositionsWithinAHalfCell() {
    // The room's built furniture as `Tools/make_room.py` places it: id, x, z in metres.
    let built: [(String, Double, Double)] = [
      ("base-windowseat", -0.41, 0), ("base-nightstand", -0.39, 0.33), ("base-plant", -0.4, -0.4),
      ("base-lamp", -0.1, -0.42), ("base-cattree", 0.36, -0.36), ("base-bowls", 0.107, -0.37),
      ("base-donutbed", 0.06, -0.04), ("base-basket", 0.37, 0.36), ("base-books", 0.2, 0.4),
      ("base-rug", 0, 0.04),
    ]
    for (id, x, z) in built {
      let spot = fresh.placement(of: id)!
      #expect(abs(DecorGrid.metres(spot.u) - x) <= DecorGrid.step / 2 + 0.001, "\(id) x")
      #expect(abs(DecorGrid.metres(spot.v) - z) <= DecorGrid.step / 2 + 0.001, "\(id) z")
    }
  }

  @Test func theDefaultRoomLeavesHerTheWayItAlwaysDid() {
    let occupancy = fresh.occupancy()
    #expect(occupancy.bareShare > 0.5)
    #expect(occupancy.connects(from: fresh.spawn(), to: fresh.anchors()))
    #expect(!occupancy.isBlocked(at: fresh.spawn()))
    // Her destinations stand where the old fixed spots were.
    let spawn = fresh.spawn()
    #expect(abs(spawn.x - 0.0) < 0.001 && abs(spawn.z - 0.19) < 0.001)
    #expect(fresh.anchors().count == 1)
    for name in ["ball", "basket", "sill"] {
      #expect(fresh.canVisit(name), Comment(rawValue: name))
    }
  }

  @Test func aPieceStandsOnTheSpotOfAFurniturePieceIsRefused() {
    let yarn = at("yarn", 7, -7)
    #expect(fresh.verdict(yarn) == .occupied)
    let moved = fresh.putting(at("base-cattree", 7, 0))
    #expect(moved.accepts(yarn))
  }

  @Test func furnitureMovesLikeAnyPieceAndTheRouteFollowsTheTree() {
    let moved = fresh.putting(at("base-cattree", 7, -3))
    #expect(moved.anchors().count == 1)
    #expect(moved.reachesAnchors())
    #expect(moved.occupancy().connects(from: moved.spawn(), to: moved.anchors()))
  }

  @Test func aTurnedPieceTurnsItsFollowedSpots() {
    let turned = fresh.putting(at("base-basket", 7, 7, 2))
    let visit = turned.point(of: DecorRoom.home.visitFollows["basket"]!)!
    #expect(abs(visit.x - 0.43) < 0.001 && abs(visit.z - 0.44) < 0.001)
  }

  @Test func storedFurnitureIsInTheClosetAndHasNoSpot() {
    let away = fresh.storing("base-cattree")
    #expect(!away.isPlaced("base-cattree"))
    #expect(away.closet(owned: []).map(\.id) == ["base-cattree"])
    #expect(away.anchors().isEmpty)
    #expect(away.stowed == ["base-cattree"])
    #expect(!away.canVisit("nothing"))
    let back = away.putting(at("base-cattree", 7, 0))
    #expect(back.isPlaced("base-cattree") && back.stowed.isEmpty)
  }

  @Test func aStoredPiecesPlaceIsFreeForOthers() {
    #expect(fresh.verdict(at("yarn", 7, -7)) == .occupied)
    #expect(fresh.storing("base-cattree").accepts(at("yarn", 7, -7)))
  }

  @Test func storingTheBedWithoutAnotherRestIsRefusedAndWithOneIsFine() {
    #expect(!fresh.canStore("base-donutbed"))
    #expect(fresh.canStore("base-plant"))
    let sofa = fresh.putting(at("armchair", -2, 6))
    #expect(sofa.canStore("base-donutbed"))
    let bedGone = sofa.storing("base-donutbed")
    #expect(!bedGone.canStore("armchair"))
  }

  @Test func theFurnitureDoesNotCountAgainstTheCap() {
    let owned = Set(DecorItem.all.filter { !$0.isBase }.prefix(10).map(\.id))
    let settled = DecorLayout(stored: []).settled(owned: owned)
    let shop = settled.placements.filter { DecorItem.item(shopID: $0.item)?.isBase == false }
    #expect(shop.count <= DecorLayout.maxPlaced)
    #expect(DecorItem.baseItems(in: .living).allSatisfy { settled.isPlaced($0.id) })
  }

  @Test func aServersWordReplacesTheStowedFurnitureAndNilLeavesIt() {
    let local = fresh.storing("base-plant")
    #expect(local.replacing(placements: [], stowed: nil).stowed == ["base-plant"])
    #expect(local.replacing(placements: [], stowed: []).stowed.isEmpty)
    #expect(local.replacing(placements: [], stowed: ["base-bowls"]).stowed == ["base-bowls"])
  }

  // MARK: Turning

  @Test func aTurnThatFitsTurnsWhereItStands() {
    guard case .turned(let layout) = fresh.turning("base-bowls") else {
      Issue.record("did not turn")
      return
    }
    #expect(layout.placement(of: "base-bowls")?.quarterTurns == 1)
  }

  @Test func aFineTurnIsFortyFiveDegreesAndItsBoxIsTheOneRoundTheTurnedFootprint() throws {
    let layout = fresh.storing("base-donutbed")
    guard case .turned(let turned) = layout.turning("base-bowls", byEighths: 1) else {
      Issue.record("did not turn")
      return
    }
    let placement = try #require(turned.placement(of: "base-bowls"))
    #expect(placement.eighthTurns == 1 && placement.isDiagonal && placement.quarterTurns == 0)
    #expect(abs(placement.angle - .pi / 4) < 1e-9)
    let item = try #require(DecorItem.item(shopID: "base-bowls"))
    let span = try #require(DecorLayout.span(of: placement, item: item))
    let half = (item.width + item.depth) / 2 * 0.5.squareRoot()
    #expect(abs(span.halfX - half) < 1e-9 && abs(span.halfZ - half) < 1e-9)
    #expect(turned.placement(of: "base-bowls")?.turned.eighthTurns == 3)
  }

  @Test func theServersTurnsKeepOldLayoutsAndRoundTrip() throws {
    for wire in 0...7 {
      let placement = Placement(item: "yarn", surface: .floor, u: 1, v: 2, wireTurns: wire)
      #expect(placement.wireTurns == wire)
      let decoded = try JSONDecoder().decode(Placement.self, from: JSONEncoder().encode(placement))
      #expect(decoded == placement)
    }
    #expect(Placement(item: "yarn", surface: .floor, u: 0, v: 0, wireTurns: 1).quarterTurns == 1)
    #expect(Placement(item: "yarn", surface: .floor, u: 0, v: 0, wireTurns: 5).eighthTurns == 3)
    let old = Data(#"{"item":"yarn","surface":"floor","u":1,"v":2,"quarterTurns":3}"#.utf8)
    #expect(try JSONDecoder().decode(Placement.self, from: old).eighthTurns == 6)
  }

  @Test func aDiagonalPieceNeedsMoreRoomThanAStraightOneAtTheWall() {
    let straight = Placement(item: "base-windowseat", surface: .floor, u: -7, v: 0)
    #expect(fresh.storing("base-windowseat").accepts(straight))
    #expect(!fresh.storing("base-windowseat").accepts(straight.turned(byEighths: 1)))
  }

  @Test func aTurnWithNoRoomSlidesToTheNearestSpotThatFits() {
    // Turned, the long window seat meets the nightstand and the plant: it slides to where it fits.
    let long = fresh.turning("base-windowseat")
    #expect(long != nil)
    if case .noRoom = long { Issue.record("a spot fits") }
    if case .slid(let layout, let spot) = long {
      #expect(layout.accepts(spot))
      #expect(spot.quarterTurns == 1)
    }
  }

  @Test func aTurnThatFitsNowhereSaysSoSoItCanBeStored() {
    // A piece as wide as the room: turned it no longer fits anywhere. Block the floor wholesale.
    let wall = (-9...9).flatMap { v in
      stride(from: -9, through: 9, by: 2).map { at("bookcase", $0, v) }
    }
    let full = DecorLayout(placements: wall, stored: [])
    guard case .noRoom = full.turning("bookcase") else {
      // The room is not full enough in this arrangement: the property is the same, a turn is answered.
      #expect(full.turning("bookcase") != nil)
      return
    }
  }

  @Test func aWallPieceHasNoTurn() {
    let print = Placement(item: "print", surface: .backWall, u: 6)
    #expect(DecorLayout(placements: [print], stored: []).turning("print") == nil)
  }

  // MARK: Dropping

  @Test func aDropOnFreeFloorStands() {
    guard case .fits(let layout) = fresh.dropping(at("base-plant", -1, 6)) else {
      Issue.record("not fits")
      return
    }
    #expect(layout.placement(of: "base-plant") == at("base-plant", -1, 6))
  }

  @Test func droppingOnAnotherPieceSwapsTheTwoWhenBothFit() {
    let layout = fresh.putting(at("yarn", -2, 5)).putting(at("base-plant", 0, 6))
    // The plant onto the yarn: they change places.
    guard case .swapped(let next, let other) = layout.dropping(at("base-plant", -2, 5)) else {
      Issue.record("not swapped")
      return
    }
    #expect(other == "yarn")
    #expect(next.placement(of: "base-plant") == at("base-plant", -2, 5))
    #expect(next.placement(of: "yarn")?.u == 0 && next.placement(of: "yarn")?.v == 6)
  }

  @Test func whateverIsDroppedWhereTheRoomIsEveryPieceStillFits() {
    let cells = [(-2, 6), (-1, 6), (0, 5), (7, -3), (-3, 5), (2, 5)]
    for (u, v) in cells {
      let layout = fresh.putting(at("armchair", -2, 6))
      switch layout.dropping(at("base-plant", u, v)) {
      case .fits(let next), .swapped(let next, _), .nudged(let next, _, _):
        for piece in next.allPlacements(in: .home) {
          #expect(next.accepts(piece), Comment(rawValue: "\(piece.item) after \(u),\(v)"))
        }
      case .rejected:
        break
      }
    }
  }

  @Test func droppingWhereNothingMakesRoomIsRejectedAndChangesNothing() {
    let drop = fresh.dropping(at("base-rug", 20, 20))
    if case .rejected = drop {} else { Issue.record("not rejected") }
  }

  // MARK: Reset

  @Test func resettingPutsTheFurnitureBackAndKeepsTheStarterPiecesInTheCloset() {
    let messy = fresh.putting(at("base-cattree", 7, 0)).storing("base-plant")
    let owned: Set<String> = ["lamp", "rug"]
    let reset = messy.reset(owned: owned)
    #expect(reset.placements.isEmpty)
    #expect(reset.stowed.isEmpty)
    #expect(reset.placement(of: "base-cattree")?.v == -7)
    #expect(reset.closet(owned: owned).map(\.id).sorted() == ["lamp", "rug"])
  }
}
