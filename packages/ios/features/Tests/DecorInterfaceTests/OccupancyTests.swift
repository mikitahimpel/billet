import Testing

@testable import DecorInterface

@Suite struct OccupancyTests {
  private let room = DecorRoom.home

  @Test func theRoomAsItComesLeavesHerAWayToEverywhereShesGoes() {
    let occupancy = DecorLayout().occupancy(in: room)
    #expect(occupancy.connects(from: room.spawn, to: room.stops))
    #expect(occupancy.freeShare > 0.4)
    #expect(!occupancy.isBlocked(at: room.spawn))
    for anchor in room.stops { #expect(!occupancy.isBlocked(at: anchor)) }
  }

  @Test func aSolidPieceBlocksItsCellsAndAFlatOneDoesNot() {
    let chair = DecorLayout(
      placements: [Placement(item: "armchair", surface: .floor, u: -6, v: 6)], stored: [])
    #expect(chair.occupancy(in: room).isBlocked(u: -6, v: 6))
    let rug = DecorLayout(
      placements: [Placement(item: "rug", surface: .floor, u: -6, v: 6)], stored: [])
    #expect(!rug.occupancy(in: room).isBlocked(u: -6, v: 6))
  }

  @Test func blockingHerOnlyWayIsRefused() {
    let spawn = room.spawn
    let occupancy = Occupancy(spans: [Span(x: 0, z: 0.31, halfX: 1, halfZ: 0.1)])
    #expect(occupancy.isBlocked(at: (0.2, 0.31)))
    #expect(!occupancy.connects(from: spawn, to: [(0.2, 0.45)]))
  }

  @Test func theNearestFreeCellIsTheCellItselfWhenFree() {
    let occupancy = DecorLayout().occupancy(in: room)
    let free = occupancy.nearestFree(to: (-0.3, 0.3))
    #expect(free.map { DecorGrid.cell($0.x) } == -6)
    let onTheBed = occupancy.nearestFree(to: (0.06, -0.04))
    #expect(onTheBed.map { occupancy.isBlocked(at: $0) } == false)
  }

  @Test func theRouteGoesAroundABlockedPatch() {
    let occupancy = Occupancy(spans: [Span(x: 0, z: 0, halfX: 0.1, halfZ: 0.3)])
    let corners = occupancy.route(from: (-0.4, 0), to: (0.4, 0))
    #expect(corners != nil)
    #expect(corners?.isEmpty == false)
    var at: Occupancy.Point = (-0.4, 0)
    for corner in corners ?? [] {
      #expect(occupancy.clear(from: at, to: corner))
      at = corner
    }
    #expect(occupancy.clear(from: at, to: (0.4, 0)))
  }

  @Test func aStraightWalkNeedsNoCorners() {
    let occupancy = Occupancy(spans: [Span(x: 0, z: 0.4, halfX: 0.1, halfZ: 0.05)])
    #expect(occupancy.route(from: (-0.4, -0.3), to: (0.4, -0.3))?.isEmpty == true)
  }

  @Test func noRouteWhenTheGoalIsShutOff() {
    let wall = Occupancy(spans: [Span(x: 0, z: 0, halfX: 0.02, halfZ: 1)])
    #expect(wall.route(from: (-0.4, 0), to: (0.4, 0)) == nil)
  }

  @Test func theNearestFitMovesAPieceOffTheBed() {
    let layout = DecorLayout(stored: [])
    let onTheBed = Placement(item: "monstera", surface: .floor, u: 1, v: -1)
    #expect(layout.verdict(onTheBed) == .occupied)
    let fit = layout.nearestFit(to: onTheBed)
    #expect(fit != nil)
    #expect(fit.map { layout.accepts($0) } == true)
  }

  @Test func theVerdictNamesWhyAPieceIsRefused() {
    let layout = DecorLayout()
    #expect(
      layout.verdict(Placement(item: "armchair", surface: .floor, u: 9, v: 9)) == .outsideRoom)
    #expect(layout.verdict(Placement(item: "print", surface: .floor, u: 0, v: 0)) == .wrongSurface)
    #expect(layout.verdict(Placement(item: "yarn", surface: .floor, u: -6, v: 6)) == .fits)
  }
}
