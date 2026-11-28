import Foundation
import Testing

@testable import DecorInterface

/// No way of hers passes through a piece, wherever the player stands or turns one: the walks she is sent on, the
/// hop down from her bed, the pounce on the ball and the jump up onto a seat.
@Suite struct CatWaysTests {
  private struct Lcg: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return state
    }
  }

  private func spans(
    _ layout: DecorLayout, without piece: String? = nil
  ) -> [(item: String, span: Span)] {
    layout.allPlacements(in: .home).compactMap { placement in
      guard placement.surface == .floor, placement.item != piece,
        let item = DecorItem.item(shopID: placement.item), !item.isFlat,
        let span = DecorLayout.span(of: placement, item: item)
      else { return nil }
      return (item.id, span)
    }
  }

  private func pieceCrossed(
    from a: Occupancy.Point, to b: Occupancy.Point, in layout: DecorLayout,
    without piece: String? = nil
  ) -> String? {
    spans(layout, without: piece).first { $0.span.isCrossed(from: a, to: b) }?.item
  }

  /// Every floor stop she walks between, by name.
  private func stops(_ layout: DecorLayout) -> [(name: String, point: Occupancy.Point)] {
    var stops: [(String, Occupancy.Point)] = [("bed side", layout.spawnSpot())]
    for name in DecorRoom.home.visitFollows.keys.sorted() where layout.canVisit(name) {
      if let stop = layout.visitStop(name) { stops.append((name, stop)) }
    }
    for (index, anchor) in layout.anchors().enumerated() {
      stops.append(("anchor \(index)", anchor))
    }
    for plan in layout.catSpots() { stops.append((plan.item, plan.approach)) }
    return stops
  }

  /// What is wrong with her ways in `layout`, each as a line; empty when nothing is.
  private func faults(_ layout: DecorLayout) -> [String] {
    var faults: [String] = []
    let occupancy = layout.occupancy()
    let stops = stops(layout)
    for from in stops {
      for to in stops where from.name != to.name {
        guard let corners = occupancy.route(from: from.point, to: to.point) else {
          faults.append("no way from \(from.name) to \(to.name)")
          continue
        }
        var at = from.point
        for corner in corners + [to.point] {
          if let piece = pieceCrossed(from: at, to: corner, in: layout) {
            faults.append("\(from.name) to \(to.name) goes through \(piece)")
          }
          at = corner
        }
      }
    }
    if let home = layout.catHome() {
      let piece = pieceCrossed(
        from: home.seat, to: layout.spawnSpot(), in: layout, without: home.item)
      if let piece { faults.append("the hop off \(home.item) goes through \(piece)") }
    }
    if let ball = layout.visitStop("ball"), layout.canHop(from: layout.spawnSpot(), to: ball),
      let piece = pieceCrossed(from: layout.spawnSpot(), to: ball, in: layout)
    {
      faults.append("the pounce on the ball goes through \(piece)")
    }
    for plan in layout.catSpots() {
      guard let top = plan.top else { continue }
      let piece = pieceCrossed(from: plan.approach, to: top.point, in: layout, without: plan.item)
      if let piece { faults.append("the jump onto \(plan.item) goes through \(piece)") }
    }
    return faults
  }

  private static let solidFloorPieces: [String] = DecorItem.all.filter {
    $0.mount == .floor && !$0.isFlat && ($0.base?.space ?? .living) == .living
  }.map(\.id)

  @Test func theRoomAsItComesHasNoWayThroughAPiece() {
    #expect(faults(DecorLayout()) == [])
  }

  @Test(arguments: solidFloorPieces)
  func aPieceStoodAnywhereAtAnyTurnIsGoneRound(_ item: String) {
    let fresh = DecorLayout()
    var stood = 0
    for u in -Occupancy.reach...Occupancy.reach {
      for v in -Occupancy.reach...Occupancy.reach {
        // Every other cell, and the turns by turn: the whole grid at every turn says no more and takes minutes.
        for turn in 0..<8 where (u + v + turn).isMultiple(of: 2) {
          let placement = Placement(item: item, surface: .floor, u: u, v: v, eighthTurns: turn)
          guard fresh.verdict(placement) == .fits else { continue }
          stood += 1
          let found = faults(fresh.putting(placement))
          #expect(found == [], "\(item) at \(u), \(v) turned \(turn)")
        }
      }
    }
    // The room's own pieces fit where they stand, so each is tried at least there.
    if DecorItem.item(shopID: item)?.isBase == true { #expect(stood > 0) }
  }

  @Test func aRoomRearrangedAtRandomHasNoWayThroughAPiece() {
    var random = Lcg(state: 7)
    let pieces = Self.solidFloorPieces
    var rearranged = 0
    for _ in 0..<1200 {
      var layout = DecorLayout()
      var moves: [String] = []
      for _ in 0..<Int.random(in: 1...5, using: &random) {
        guard let item = pieces.randomElement(using: &random) else { continue }
        let placement = Placement(
          item: item, surface: .floor, u: Int.random(in: -9...9, using: &random),
          v: Int.random(in: -9...9, using: &random),
          eighthTurns: Int.random(in: 0..<8, using: &random))
        guard layout.verdict(placement) == .fits else { continue }
        layout = layout.putting(placement)
        moves.append("\(item) at \(placement.u), \(placement.v) turned \(placement.eighthTurns)")
      }
      guard !moves.isEmpty else { continue }
      rearranged += 1
      #expect(faults(layout) == [], "\(moves.joined(separator: "; "))")
    }
    #expect(rearranged > 100)
  }

  @Test func aStopInAPiecesMarginIsLeftWithoutCuttingItsCorner() throws {
    // Beside the left edge of a wide piece, level with its far corner: the straight way to the other side cuts it.
    let piece = Span(x: 0, z: 0, halfX: 0.2, halfZ: 0.1)
    let occupancy = Occupancy(spans: [piece])
    let stop: Occupancy.Point = (-0.22, 0.08)
    let far: Occupancy.Point = (0.3, -0.3)
    #expect(occupancy.isBlocked(at: stop))
    let corners = try #require(occupancy.route(from: stop, to: far))
    var at = stop
    for corner in corners + [far] {
      #expect(!piece.isCrossed(from: at, to: corner))
      at = corner
    }
    #expect(occupancy.clear(from: corners.last ?? stop, to: far))
  }

  @Test func sheDoesNotSqueezeBetweenTwoPiecesCloserThanSheIsWide() throws {
    // A slit of two centimetres between two blocks right across the floor, a stop in the margin on each side.
    let left = Span(x: -0.26, z: 0, halfX: 0.25, halfZ: 0.1)
    let right = Span(x: 0.26, z: 0, halfX: 0.25, halfZ: 0.1)
    let occupancy = Occupancy(spans: [left, right])
    #expect(!occupancy.crossesPiece(from: (0, -0.12), to: (0, 0.12)))
    #expect(occupancy.route(from: (0, -0.12), to: (0, 0.12)) == nil)
  }

  @Test func touchingAPiecesEdgeIsNotThroughIt() {
    let piece = Span(x: 0, z: 0, halfX: 0.1, halfZ: 0.1)
    #expect(!piece.isCrossed(from: (-0.3, 0.1), to: (0.3, 0.1)))
    #expect(piece.isCrossed(from: (-0.3, 0.09), to: (0.3, 0.09)))
    #expect(piece.isCrossed(from: (0, 0), to: (0.3, 0)))
    #expect(!piece.isCrossed(from: (0.11, -0.3), to: (0.11, 0.3)))
    #expect(piece.isCrossed(from: (0.11, -0.3), to: (0.11, 0.3), margin: 0.02))
    #expect(piece.isCrossed(from: (-0.3, -0.25), to: (0.3, 0.25)))
  }

  @Test func sheStopsANoseOffAPieceSheFacesWhereTheFloorIsOpen() throws {
    let tree = try #require(DecorLayout().anchors().first)
    let treeEdge = DecorGrid.metres(7) - 0.1
    #expect(treeEdge - tree.x >= Occupancy.noseReach || -0.25 - tree.z <= -Occupancy.noseReach)

    let post = Placement(item: "scratchpost", surface: .floor, u: -1, v: 7)
    let onlyHerBed = Set(DecorItem.baseItems.map(\.id)).subtracting(["base-donutbed"])
    let layout = DecorLayout(placements: [post], stored: onlyHerBed)
    let plan = try #require(layout.catSpots().first { $0.use == .post })
    #expect(layout.occupancy().distanceToPiece(from: plan.approach) >= Occupancy.noseReach)
  }

  @Test func inACrowdedCornerSheStillComesUpToThePieceAHandsWidthOff() throws {
    // The post between the bed, the nightstand and the books: no cell a nose off it is free.
    let layout = DecorLayout().putting(Placement(item: "scratchpost", surface: .floor, u: -1, v: 7))
    let plan = try #require(layout.catSpots().first { $0.use == .post })
    let off = layout.occupancy().distanceToPiece(from: plan.approach)
    #expect(off > 0.04 && off < Occupancy.noseReach)
  }

  @Test func sheHopsOffHerBedToFloorWithNothingInTheWay() throws {
    // The post right where she steps down.
    let layout = DecorLayout().putting(Placement(item: "scratchpost", surface: .floor, u: 0, v: 6))
    let home = try #require(layout.catHome())
    let spot = layout.spawnSpot()
    #expect(!layout.occupancy().isSolid(at: spot))
    #expect(pieceCrossed(from: home.seat, to: spot, in: layout, without: home.item) == nil)
    #expect(spot.x != layout.spawn().x || spot.z != layout.spawn().z)
  }

  @Test func shePouncesOnTheBallOnlyWithNothingBetweenAndNotFromAfar() throws {
    let fresh = DecorLayout()
    let ball = try #require(fresh.visitStop("ball"))
    #expect(fresh.canHop(from: fresh.spawnSpot(), to: ball))

    let far = fresh.putting(Placement(item: "base-rug", surface: .floor, u: -3, v: 6))
    let farBall = try #require(far.visitStop("ball"))
    #expect(!far.canHop(from: far.spawnSpot(), to: farBall))

    #expect(!fresh.canHop(from: (-0.2, -0.45), to: (-0.05, -0.45)))
  }
}
