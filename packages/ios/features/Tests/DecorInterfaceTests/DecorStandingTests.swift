import Foundation
import Testing

@testable import DecorInterface

/// She walks to a piece and never into it: every floor point she is sent to is free floor, whatever the player stood
/// on the stops she goes to.
@Suite struct DecorStandingTests {
  private let fresh = DecorLayout()

  private func at(_ id: String, _ u: Int, _ v: Int, turns: Int = 0) -> Placement {
    Placement(item: id, surface: .floor, u: u, v: v, eighthTurns: turns)
  }

  private func inside(_ point: Occupancy.Point, _ layout: DecorLayout) -> Bool {
    layout.allPlacements(in: .home).contains { placement in
      guard placement.surface == .floor, let item = DecorItem.item(shopID: placement.item),
        !item.isFlat,
        let span = DecorLayout.span(of: placement, item: item)
      else { return false }
      return abs(point.x - span.x) < span.halfX && abs(point.z - span.z) < span.halfZ
    }
  }

  private var stops: [(name: String, point: Occupancy.Point, piece: String)] {
    DecorRoom.home.visitFollows.compactMap { name, follow in
      fresh.point(of: follow).map { (name, $0, follow.piece) }
    }
  }

  @Test func aStopThatIsFreeStaysWhereItIs() {
    for (name, stop, piece) in stops {
      let spot = fresh.standing(near: stop, beside: piece)
      #expect(spot?.x == stop.x && spot?.z == stop.z, "\(name)")
    }
  }

  @Test func theNightstandStandingOnTheWindowSeatsStopMovesHerToFreeFloorBesideIt() throws {
    let stop = try #require(fresh.point(of: DecorRoom.home.visitFollows["sill"]!))
    let layout = fresh.putting(at("base-nightstand", -4, 1))
    #expect(inside(stop, layout), "the stop is inside the nightstand now")
    #expect(layout.occupancy().isBlocked(at: stop))
    if let spot = layout.standing(near: stop, beside: "base-windowseat") {
      #expect(!inside(spot, layout))
      #expect(!layout.occupancy().isBlocked(at: spot))
      #expect(hypot(spot.x - stop.x, spot.z - stop.z) <= 0.15)
    }
  }

  @Test func noStopIsEverInsideAPieceWhereverTheNightstandIsPutAndHoweverItIsTurned() {
    var checked = 0
    for turns in 0..<8 {
      for v in stride(from: -8, through: 8, by: 2) {
        for u in stride(from: -8, through: 8, by: 2) {
          let layout = fresh.putting(at("base-nightstand", u, v, turns: turns))
          for (name, stop, piece) in stops {
            guard let spot = layout.standing(near: stop, beside: piece) else { continue }
            checked += 1
            #expect(
              !inside(spot, layout), "\(name) with the nightstand at \(u),\(v) turned \(turns)")
          }
          let spawn = layout.spawnSpot()
          #expect(
            !inside(spawn, layout), "her spawn with the nightstand at \(u),\(v) turned \(turns)")
        }
      }
    }
    #expect(checked > 0)
  }

  @Test func aWalkToAStopNeverCrossesAPiece() throws {
    let stop = try #require(fresh.point(of: DecorRoom.home.visitFollows["sill"]!))
    let layout = fresh.putting(at("base-nightstand", -4, 1)).putting(
      at("armchair", -2, 5, turns: 1))
    let occupancy = layout.occupancy()
    let spot = layout.standing(near: stop, beside: "base-windowseat") ?? layout.spawnSpot()
    let corners = try #require(occupancy.route(from: layout.spawnSpot(), to: spot))
    var from = layout.spawnSpot()
    for corner in corners + [spot] {
      #expect(occupancy.clear(from: from, to: corner))
      #expect(!inside(corner, layout))
      from = corner
    }
  }

  @Test func aVisitWhoseStopIsBuriedBeyondReachIsCutOff() throws {
    let stop = try #require(fresh.point(of: DecorRoom.home.visitFollows["sill"]!))
    #expect(fresh.canVisit("sill"))
    let buried = fresh.putting(at("base-nightstand", -4, 1))
    // Either she has a free spot within a hand of it, or the visit is gone; never a stop inside the piece.
    #expect(
      buried.canVisit("sill") == (buried.standing(near: stop, beside: "base-windowseat") != nil))
  }
}
