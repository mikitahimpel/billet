import Pet
import Testing
import simd

@testable import PetSceneReality

/// The cat moves along the room's surfaces: walks on each level round what stands there, jumps
/// between them at their edges, and never goes through anything.
@MainActor
@Suite struct GenzCatWayTests {
  static var layouts: [GenzLayout] {
    [RoomFurniture.cosyNook, .retroDen].flatMap { furniture in
      [false, true].map { idol in
        var layout = GenzLayout.of(furniture, idolProps: idol)
        layout.catBody = CatModel.gingerChonk.footprint
        return layout
      }
    }
  }

  @Test func theRoomHasLevelsTheCatJumpsBetween() throws {
    for layout in Self.layouts {
      let levels = layout.catLevels
      #expect(levels.contains { $0.kind == .floor }, "\(layout.key)")
      #expect(levels.contains { $0.id == GenzCatLevel.homeID }, "\(layout.key)")
      #expect(levels.contains { $0.kind == .bed }, "\(layout.key)")
      let reach = layout.catReachableLevels(from: layout.catHomeLevel)
      #expect(reach.contains(GenzCatLevel.floorID), "\(layout.key): the seat leads down")
      #expect(reach.count >= 3, "\(layout.key): \(reach)")
    }
  }

  /// From the seat to the cat bed: a walk, a jump down, a walk round the pouf and the plants,
  /// a hop in. Each walk keeps the walking body clear of what is on its level, and each jump is
  /// one a cat can make.
  @Test(.timeLimit(.minutes(2))) func theWayToTheBedWalksAndJumps() throws {
    for layout in Self.layouts {
      let bed = try #require(
        layout.catLevels.first { $0.kind == .bed }, "\(layout.key)")
      let home = layout.onCatSurface(SIMD2(layout.cat.spot.x, layout.cat.spot.y))
      let goal = try #require(
        layout.catSpot(near: bed.box.centre, on: bed, obstacles: layout.catObstacles(on: bed.id)))
      let ways = layout.catWay(from: home, on: layout.catHomeLevel, to: goal, on: bed.id)
      let jumps = ways.compactMap { if case .jump(let jump) = $0 { jump } else { nil } }
      #expect(jumps.count >= 2, "\(layout.key): \(ways)")
      #expect(jumps.first?.rise ?? 0 < 0, "\(layout.key): down off the seat first")
      #expect(jumps.last?.toLevel == bed.id, "\(layout.key)")
      var at = home
      var level = layout.catHomeLevel
      for way in ways {
        switch way {
        case .walk(let to, let on):
          #expect(on == level, "\(layout.key): walks on the level it is on")
          Self.expectClear(layout, from: at, to: to, on: on)
          at = to
        case .jump(let jump):
          #expect(jump.fromLevel == level)
          #expect(simd_distance(at, jump.from) < 0.01, "\(layout.key): jumps from where it is")
          #expect(abs(jump.rise) <= GenzLayout.catJumpHeight)
          #expect(simd_distance(jump.from, jump.to) <= layout.cat.length * GenzLayout.catJumpReach)
          at = jump.to
          level = jump.toLevel
        }
      }
      #expect(level == bed.id)
      #expect(simd_distance(at, goal) < 0.01, "\(layout.key): gets there")
    }
  }

  static func expectClear(_ layout: GenzLayout, from: SIMD2<Float>, to: SIMD2<Float>, on level: Int)
  {
    let isHome = level == GenzCatLevel.homeID
    let obstacles = (isHome ? layout.catObstacles : layout.catObstacles(on: level)).filter {
      !$0.sitOnTop
    }
    let ground = isHome ? layout.cat.spot.z : layout.catLevel(level)?.top ?? 0
    let gap = to - from
    let heading = CatTrip.heading(from: from, to: to)
    let steps = max(Int(simd_length(gap) / 0.05), 1)
    for step in 0...steps {
      let point = from + gap * (Float(step) / Float(steps))
      #expect(
        layout.catBodyIsClear(
          at: point, heading: heading, ground: ground, obstacles: obstacles,
          shape: isHome ? nil : layout.catBody.standing),
        "\(layout.key): walking through something at \(point) on \(level)")
    }
  }

  /// Lying down, the cat keeps further off things than standing: its resting body is wider.
  @Test func aRestingCatKeepsFurtherOff() throws {
    var layout = GenzLayout.of(.cosyNook)
    layout.catBody = CatModel.gingerChonk.footprint
    let mugs = try #require(layout.pieces.first { $0.piece.kind == .mugs })
    // Side-on to the mugs, a little more than its standing half-width off them.
    let beside = SIMD2(
      mugs.centre.x + mugs.piece.kind.size.x / 2 + layout.cat.length * 0.36, mugs.centre.y)
    let level = GenzCatLevel.homeID
    #expect(!layout.catIsCrowded(at: beside, heading: 0, on: level, resting: false))
    #expect(layout.catIsCrowded(at: beside, heading: 0, on: level, resting: true))
    let rest = layout.catRestSpot(near: beside, on: level, heading: 0)
    #expect(Self.turnFits(layout, rest))
    #expect(simd_distance(rest, beside) > 0.05)
  }

  private static func turnFits(_ layout: GenzLayout, _ at: SIMD2<Float>) -> Bool {
    GenzLayout.turns.contains {
      !layout.catIsCrowded(at: at, heading: $0, on: GenzCatLevel.homeID, resting: true)
    }
  }

  /// A piece moved onto where the cat lies: the cat is crowded there, and has somewhere near to
  /// go that it fits.
  @Test func aPieceMovedOntoTheCatMovesIt() throws {
    var layout = GenzLayout.of(.cosyNook)
    layout.catBody = CatModel.gingerChonk.footprint
    let home = layout.catRestSpot(
      near: layout.onCatSurface(SIMD2(layout.cat.spot.x, layout.cat.spot.y)),
      on: GenzCatLevel.homeID, heading: 0)
    let mugs = try #require(layout.pieces.firstIndex { $0.piece.kind == .mugs })
    #expect(
      !layout.catIsCrowded(at: home, heading: 0, on: GenzCatLevel.homeID, resting: true)
        || Self.turnFits(layout, home))
    layout.pieces[mugs].centre.x = home.x
    layout.pieces[mugs].centre.y = home.y
    #expect(layout.catIsCrowded(at: home, heading: 0, on: GenzCatLevel.homeID, resting: true))
    let moved = layout.catRestSpot(near: home, on: GenzCatLevel.homeID, heading: 0)
    #expect(simd_distance(moved, home) > layout.cat.length * 0.3)
    #expect(Self.turnFits(layout, moved))
  }

  /// On the floor, the cat goes round the pouf, the plants and the bookshelf, not through them.
  @Test(.timeLimit(.minutes(2))) func onTheFloorItGoesRoundTheFurniture() throws {
    for layout in Self.layouts {
      let floor = try #require(layout.catLevel(GenzCatLevel.floorID))
      let obstacles = layout.catObstacles(on: floor.id)
      #expect(obstacles.count >= 5, "\(layout.key)")
      let from = try #require(layout.catSpot(near: [1.0, 5.4], on: floor, obstacles: obstacles))
      let to = try #require(layout.catSpot(near: [6.8, 3.3], on: floor, obstacles: obstacles))
      var at = from
      for point in layout.catRoute(from: from, to: to, on: floor.id) {
        Self.expectClear(layout, from: at, to: point, on: floor.id)
        at = point
      }
    }
  }
}
