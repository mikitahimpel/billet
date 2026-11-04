import Foundation
import Pet
import PetScene
import RealityKit
import Testing
import simd

@testable import PetSceneReality

/// The cat never walks, sits or lies inside a pillow, cushion, folded throw or the cardigan: each
/// is something to go round, or, for the cardigan, to get up on and lie on top of.
/// The walks and spots take a few seconds on the main actor, so they yield it as they go to the
/// stages other tests are loading on it.
@MainActor
@Suite struct GenzCatObstacleTests {
  /// Every room the cat lives on a piece of furniture in, and one with the generated props: the
  /// walks are slow, and the cosy nook has the props the cat walks round and lies on (the throw
  /// and the books on the seat). ``GenzCatPathTests`` checks the retro den's.
  private var layouts: [(String, GenzLayout)] {
    RoomFurniture.allCases.map { furniture in
      ("windowSeat \(furniture)", GenzLayout.of(furniture))
    } + [("windowSeat cosyNook idol", GenzLayout.of(.cosyNook, idolProps: true))]
  }

  /// The spots the brain sends the cat to, as `GenzRoom.resolve` works them out: home, a grid of
  /// roaming targets over its whole top, beside the things on it, and up on the cardigan.
  private func spots(_ layout: GenzLayout) -> [SIMD2<Float>] {
    let home = layout.onCatSurface(SIMD2(layout.cat.spot.scene.x, layout.cat.spot.scene.z))
    var out = [home]
    if let surface = layout.catSurface {
      for a in stride(from: Float(0), through: 1, by: 0.25) {
        for b in stride(from: Float(0), through: 1, by: 0.5) {
          out.append(layout.onCatSurface(surface.min + (surface.max - surface.min) * [a, b]))
        }
      }
    }
    for obstacle in layout.catObstacles {
      out.append(
        obstacle.sitOnTop
          ? layout.catSpotOnTop(of: obstacle) : layout.onCatSurface(obstacle.box.centre))
    }
    return out
  }

  /// What the body is in, for a cat at `point` facing `heading`, `height` above its top. The feet
  /// stand inside the body's footprint, so the capsule covers them.
  private func inside(
    _ layout: GenzLayout, _ obstacles: [GenzCatObstacle], at point: SIMD2<Float>, heading: Float,
    height: Float
  ) -> GenzCatObstacle? {
    obstacles.first { obstacle in
      !layout.catBodyIsClear(at: point, heading: heading, height: height, obstacles: [obstacle])
    }
  }

  @Test func thePillowsAndThrowsAreObstacles() throws {
    let byName = Dictionary(layouts, uniquingKeysWith: { a, _ in a })
    // The window bench's four pillows and its folded throw, under the cardigan and the mugs.
    let bench = try #require(byName["windowSeat cosyNook"])
    #expect(bench.catObstacles.filter(\.builtIn).count == 5)
    #expect(bench.catObstacles.filter(\.sitOnTop).count == 1)
  }

  @Test func everySpotTheBrainPicksIsClear() async {
    for (name, layout) in layouts {
      let obstacles = layout.catObstacles
      for spot in spots(layout) {
        await Task.yield()
        let height = layout.catStandHeight(at: spot, obstacles: obstacles)
        // Whichever way the brain wants it to face, it stands so its body is clear.
        for want in stride(from: Float(-3), through: 3, by: 1.5) {
          let heading = layout.catHeading(at: spot, want: want, height: height)
          let hit = inside(layout, obstacles, at: spot, heading: heading, height: height)
          #expect(hit == nil, "\(name): at \(spot) facing \(heading) in \(String(describing: hit))")
        }
      }
    }
  }

  @Test func everyWalkGoesRound() async {
    for (name, layout) in layouts {
      let obstacles = layout.catObstacles
      let spots = spots(layout)
      var stuck = 0
      // From home to every spot, and on from each spot to the next, as a day of roaming does.
      let trips = spots.map { (spots[0], $0) } + zip(spots, spots.dropFirst()).map { ($0, $1) }
      for (start, goal) in trips {
        await Task.yield()
        let route = layout.catRoute(from: start, to: goal)
        // A step of a few centimetres that would turn its nose into a pillow, it does not take.
        if route.last != goal, simd_distance(start, goal) > layout.cat.length * 0.5 { stuck += 1 }
        var at = start
        for next in route {
          let heading = CatTrip.heading(from: at, to: next)
          let steps = max(Int(simd_distance(at, next) / 0.02), 1)
          for step in 0...steps {
            let point = at + (next - at) * (Float(step) / Float(steps))
            let height = layout.catStandHeight(at: point, obstacles: obstacles)
            let hit = inside(layout, obstacles, at: point, heading: heading, height: height)
            #expect(
              hit == nil,
              "\(name): \(start) → \(goal) passes \(point) in \(String(describing: hit))")
            if hit != nil { break }
          }
          at = next
        }
      }
      // Nearly every spot is reachable; past something that fills the top's width, the cat walks
      // as near as it gets.
      #expect(stuck <= trips.count / 10, "\(name): \(stuck) of \(trips.count) trips stuck")
    }
  }

  @Test func theCardiganIsLainOnTopOf() throws {
    let layout = GenzLayout.of(.cosyNook)
    let cardigan = try #require(layout.catObstacles.first { $0.sitOnTop })
    let spot = layout.catSpotOnTop(of: cardigan)
    #expect(cardigan.box.contains(spot))
    let height = layout.catStandHeight(at: spot)
    // On its top, sunk into the knit a little, not inside it.
    #expect(height > 0.1)
    #expect(layout.cat.spot.z + height <= cardigan.top)
    let heading = try #require(layout.catClearHeading(at: spot, want: 0.3))
    #expect(layout.catBodyIsClear(at: spot, heading: heading, height: height))
    // Beside it the cat is on the seat again.
    let beside = cardigan.box.centre + [cardigan.box.half.x + layout.cat.length, 0]
    #expect(layout.catStandHeight(at: beside) == 0)
  }
}

extension GenzCatObstacleTests {
  /// What the brain resolves its targets to in a built Window Seat room is clear of every pillow,
  /// and its cardigan is lain on top of. Run by `GenzCatBrainTests`, which builds the room anyway.
  static func theBrainsTargetsAreClear(in room: GenzRoom) throws {
    let layout = room.layout
    room.brainBody.places = room.affordances()
    let cardigan = try #require(layout.catObstacles.first { $0.sitOnTop })
    #expect(cardigan.box.contains(room.resolve(.affordance(.soft))))
    var targets: [CatTarget] = [.home, .camera]
    targets += RoomAffordance.Kind.allCases.map { .affordance($0) }
    for a in stride(from: 0.0, through: 1, by: 0.25) {
      for b in stride(from: 0.0, through: 1, by: 0.5) { targets.append(.roam(a, b)) }
    }
    for target in targets {
      let spot = room.resolve(target)
      let height = layout.catStandHeight(at: spot)
      let heading = layout.catHeading(at: spot, want: 0, height: height)
      #expect(
        layout.catBodyIsClear(at: spot, heading: heading, height: height), "\(target) at \(spot)")
    }
  }

  /// The body the obstacles are kept from is as wide as `model`'s middle and reaches its nose,
  /// measured on its mesh: the head (and whiskers) at -z, the tail at +z. Run by
  /// `CatCatalogTests`, which loads every cat anyway.
  static func theBodyFits(_ model: CatModel, _ cat: Entity) throws {
    var points: [SIMD3<Float>] = []
    func gather(_ entity: Entity) {
      if let piece = entity as? ModelEntity, let mesh = piece.model?.mesh {
        let transform = piece.transformMatrix(relativeTo: cat)
        for part in mesh.contents.models.flatMap(\.parts) {
          for p in part.positions.elements {
            let at = transform * SIMD4(p, 1)
            points.append([at.x, at.y, at.z])
          }
        }
      }
      entity.children.forEach(gather)
    }
    gather(cat)
    let length = model.anatomy.length
    let back = try #require(points.map(\.z).min())
    let front = try #require(points.map(\.z).max())
    // Across its middle, between the head and the haunches.
    let middle = points.filter {
      let share = ($0.z - back) / (front - back)
      return share > 0.35 && share < 0.65
    }
    let width =
      (try #require(middle.map(\.x).max()) - (try #require(middle.map(\.x).min()))) / length
    #expect(width / 2 <= GenzCatBody.radius + 0.01, "\(model) is \(width) of its length wide")
    // The tip of its nose, inside the capsule's round front end.
    let nose = -back / length
    #expect(nose <= GenzCatBody.reach + GenzCatBody.radius + 0.04, "\(model) nose at \(nose)")
  }
}
