import DecorInterface
import Foundation
import simd

/// A fixed set of moves, the same every run, played from sitting at `home` facing `yaw`.
struct Scenario {
  enum Cue {
    case act(String, (Stage) -> Void)
    case wait(Float)
    /// Until she has finished what she was told to do.
    case untilStill
    /// Called every frame for so many seconds, with the seconds gone.
    case each(Float, (Stage, Float) -> Void)
  }

  /// A box she jumps onto, for the picture: centre of its top and its half width.
  struct Box {
    let top: SIMD3<Float>
    let half: Float
  }

  let name: String
  let home: SIMD3<Float>
  let yaw: Float
  var lyingBodies = true
  var boxes: [Box] = []
  /// The room's pieces as the player stood them: she goes round them, and the picture and the numbers have them.
  var layout: DecorLayout?
  /// What the room view looks at, and how many pixels a room unit takes in it.
  let focus: SIMD3<Float>
  var zoom: Float = 520
  let cues: [Cue]
}

private func facing(_ dx: Float, _ dz: Float) -> Float { atan2(-dx, -dz) }

/// A piece's floor space, for the picture and to tell when she is inside it.
struct Footprint {
  let item: String
  let center: SIMD2<Float>
  let half: SIMD2<Float>
  let height: Float

  /// How deep `point` is inside, in room units; 0 outside.
  func depth(of point: SIMD2<Float>) -> Float {
    let inside = half - simd_abs(point - center)
    return max(0, min(inside.x, inside.y))
  }
}

extension DecorLayout {
  /// What stands on the Home room's floor, rugs left out.
  var footprints: [Footprint] {
    allPlacements(in: .home).compactMap { placement in
      guard placement.surface == .floor, let item = DecorItem.item(shopID: placement.item), !item.isFlat else {
        return nil
      }
      let size = DecorLayout.footprint(of: item, eighthTurns: placement.eighthTurns)
      return Footprint(
        item: item.id,
        center: [Float(DecorGrid.metres(placement.u)), Float(DecorGrid.metres(placement.v))],
        half: [Float(size.width / 2), Float(size.depth / 2)], height: Float(item.height))
    }
  }
}
private let east = facing(1, 0)

extension Scenario {
  private static func go(_ label: String, _ path: [CatWalker.Waypoint], rest: Float) -> Cue {
    .act(label) { $0.walker.go(to: .init(id: label, path: path, rest: rest)) }
  }

  /// The laser dot's way across the floor: off round the obstacle, back across, then a rest for the pounce.
  private static func dot(_ t: Float) -> SIMD3<Float> {
    let keys: [(Float, SIMD2<Float>)] = [
      (0, [-0.1, 0.1]), (0.6, [-0.1, 0.1]), (2.2, [0.3, -0.25]), (3.2, [0.3, 0.2]), (4.6, [-0.3, 0.25]),
      (5.6, [-0.05, -0.2]), (6.6, [0.2, 0.05]), (9, [0.2, 0.05]),
    ]
    let next = keys.firstIndex { $0.0 > t } ?? keys.count - 1
    let (a, b) = (keys[max(next - 1, 0)], keys[next])
    let u = min(max((t - a.0) / max(b.0 - a.0, 1e-3), 0), 1)
    let p = a.1 + (b.1 - a.1) * (u * u * (3 - 2 * u))
    return [p.x, 0, p.y]
  }

  private static let length: Float = 0.2

  /// The laser game's rule for her, as `LaserStage` has it; `chasing` off is the rule it had before, a trip to
  /// the dot each time she is free and it is far.
  private static func laser(_ name: String, chasing: Bool) -> Scenario {
    var still: Float = 0
    var last = SIMD3<Float>.zero
    var sent = 0
    return Scenario(
      name: name, home: [-0.3, 0, -0.1], yaw: east, focus: [0, 0.08, 0],
      cues: [
        .act("laser") {
          $0.walker.pace = .eager
          $0.walker.keepOut = ([0.08, -0.05], 0.09)
        },
        .each(10) { stage, t in
          let dot = dot(t)
          stage.dot = dot
          still = simd_distance(dot, last) / (1 / 60) < 0.03 ? still + 1 / 60 : 0
          last = dot
          let at = stage.walker.at
          let gap = simd_distance(dot, at)
          let short = min(0.3 * length, gap * 0.9)
          let stop = gap > 0.001 ? dot + (at - dot) / gap * short : dot
          if chasing {
            if gap > (stage.walker.moving ? 0.35 : 0.5) * length {
              stage.walker.chase(stop, id: "laser")
            } else if !stage.walker.moving, still > 0.25, sent == 0 {
              sent = 1
              stage.walker.pounce(on: stop, id: "laser")
            }
          } else if !stage.walker.moving, gap > 0.62 * length || still > 0.25 && sent == 0 {
            if gap <= 0.62 * length { sent = 1 } else { sent -= 1 }
            stage.walker.go(
              to: .init(
                id: "laser\(sent)", path: [.init(at: stop, move: .jump)], rest: facing(dot.x - at.x, dot.z - at.z),
                play: gap <= 0.62 * length))
          }
        },
        .untilStill, .wait(2),
      ])
  }

  private static let floor: Float = 0.023

  private static func floored(_ point: Occupancy.Point) -> SIMD3<Float> { [Float(point.x), floor, Float(point.z)] }

  /// The Home room as the player arranged it, her bed left out: she starts on the floor beside where it stands, goes
  /// where `way` leads, on to the open floor nearest `far` and back.
  private static func room(
    _ name: String, _ layout: DecorLayout, far: SIMD2<Float>, way: (path: [CatWalker.Waypoint], rest: Float)
  ) -> Scenario {
    let open = layout.occupancy().nearestFree(to: (Double(far.x), Double(far.y))) ?? (0, 0.45)
    return Scenario(
      name: name, home: floored(layout.spawnSpot()), yaw: facing(0, 1), layout: layout, focus: [0, 0.12, 0],
      zoom: 400,
      cues: [
        .wait(1),
        go("to the piece", way.path, rest: way.rest),
        .untilStill, .wait(1.5),
        go("past it", [.init(at: floored(open))], rest: facing(0, 1)),
        .untilStill, .wait(1),
        .act("home") { $0.walker.go(to: nil) },
        .untilStill, .wait(1),
      ])
  }

  /// To the floor beside the piece she uses for `use`, and up onto it when it is a seat, as the room plans it.
  private static func way(to use: CatUse, in layout: DecorLayout) -> (path: [CatWalker.Waypoint], rest: Float) {
    guard let plan = layout.catSpots().first(where: { $0.use == use }), let placement = layout.placement(of: plan.item)
    else { return ([], 0) }
    var path = [CatWalker.Waypoint(at: floored(plan.approach))]
    if let top = plan.top {
      path.append(.init(at: [Float(top.point.x), 0.014 + Float(top.height), Float(top.point.z)], move: .jump))
    }
    let toPiece = facing(
      Float(DecorGrid.metres(placement.u) - plan.approach.x), Float(DecorGrid.metres(placement.v) - plan.approach.z))
    return (path, toPiece)
  }

  /// To the ball on the rug: a pounce from beside her bed while it lies near with nothing between, else a walk.
  private static func wayToTheBall(in layout: DecorLayout) -> (path: [CatWalker.Waypoint], rest: Float) {
    guard let ball = layout.visitStop("ball") else { return ([], 0) }
    let spawn = layout.spawnSpot()
    let pounces = layout.canHop(from: spawn, to: ball)
    return (
      [.init(at: floored(ball), move: pounces ? .jump : .walk)],
      facing(Float(ball.x - spawn.x), Float(ball.z - spawn.z))
    )
  }

  /// To the floor beside the cat tree and up onto its top.
  private static func wayUpTheTree(in layout: DecorLayout) -> (path: [CatWalker.Waypoint], rest: Float) {
    guard let foot = layout.anchors().first, let tree = layout.placement(of: "base-cattree") else { return ([], 0) }
    let top: SIMD3<Float> = [Float(DecorGrid.metres(tree.u)), 0.396, Float(DecorGrid.metres(tree.v))]
    return ([.init(at: floored(foot)), .init(at: top, move: .jump)], 0.75 + .pi)
  }

  private static func placed(_ item: String, u: Int, v: Int, eighthTurns: Int = 0) -> DecorLayout {
    DecorLayout().putting(Placement(item: item, surface: .floor, u: u, v: v, eighthTurns: eighthTurns))
  }

  static let all: [Scenario] = [
    room("tree", DecorLayout(), far: [-0.2, 0.35], way: wayUpTheTree(in: DecorLayout())),
    room(
      "post", placed("scratchpost", u: -1, v: 7), far: [-0.3, 0.3],
      way: way(to: .post, in: placed("scratchpost", u: -1, v: 7))),
    room(
      "post-turned", placed("scratchpost", u: -2, v: 6, eighthTurns: 1), far: [0.3, 0.1],
      way: way(to: .post, in: placed("scratchpost", u: -2, v: 6, eighthTurns: 1))),
    room(
      "ball-past-the-tree", placed("base-cattree", u: -1, v: 5, eighthTurns: 6), far: [0.3, 0.1],
      way: wayToTheBall(in: placed("base-cattree", u: -1, v: 5, eighthTurns: 6))),
    room(
      "armchair", placed("armchair", u: -1, v: 6), far: [0.3, 0.1], way: way(to: .sofa, in: placed("armchair", u: -1, v: 6))),
    laser("laser", chasing: true),
    laser("laser-trips", chasing: false),
    Scenario(
      name: "sit-walk-sit", home: [-0.25, 0, 0], yaw: east, focus: [0, 0.08, 0],
      cues: [
        .wait(1.5),
        go("walk", [.init(at: [0.25, 0, 0])], rest: east),
        .untilStill, .wait(1.5),
      ]),
    Scenario(
      name: "turn-90", home: [0, 0, -0.1], yaw: east, focus: [0, 0.08, 0.05],
      cues: [
        .wait(1),
        go("turn 90, walk", [.init(at: [0, 0, 0.25])], rest: facing(0, 1)),
        .untilStill, .wait(1),
      ]),
    Scenario(
      name: "turn-180", home: [0.15, 0, 0], yaw: east, focus: [0, 0.08, 0],
      cues: [
        .wait(1),
        go("turn 180, walk", [.init(at: [-0.2, 0, 0])], rest: facing(-1, 0)),
        .untilStill, .wait(1),
      ]),
    Scenario(
      name: "route", home: [-0.3, 0, -0.15], yaw: east, focus: [-0.05, 0.08, 0.05],
      cues: [
        .wait(1),
        go("two legs", [.init(at: [0.15, 0, -0.15]), .init(at: [0.15, 0, 0.25])], rest: facing(-0.6, 1)),
        .untilStill, .wait(1.5),
        .act("home") { $0.walker.go(to: nil) },
        .untilStill, .wait(1),
      ]),
    Scenario(
      name: "jump", home: [-0.3, 0, 0], yaw: east, boxes: [.init(top: [0.3, 0.37, 0], half: 0.1)],
      focus: [0, 0.22, 0], zoom: 420,
      cues: [
        .wait(1),
        go("up", [.init(at: [0.05, 0, 0]), .init(at: [0.3, 0.37, 0], move: .jump)], rest: facing(-1, 0.6)),
        .untilStill, .wait(1.5),
        .act("down") { $0.walker.go(to: nil) },
        .untilStill, .wait(1),
      ]),
    Scenario(
      name: "lie", home: [0, 0, 0], yaw: facing(-0.5, 1), focus: [0, 0.08, 0],
      cues: [
        .wait(1.5),
        .act("loaf") { $0.walker.settle(.loaf) }, .wait(3),
        .act("sleep") { $0.walker.settle(.sleep) }, .wait(3),
        .act("sit") { $0.walker.settle(.sit) }, .wait(2),
      ]),
    Scenario(
      name: "lie-on-standing", home: [0, 0, 0], yaw: east, lyingBodies: false, focus: [0, 0.08, 0],
      cues: [
        .wait(1.5),
        .act("loaf") { $0.walker.settle(.loaf) }, .untilStill, .wait(2),
        .act("sit") { $0.walker.settle(.sit) }, .untilStill, .wait(1.5),
      ]),
    Scenario(
      name: "pats", home: [0, 0, 0], yaw: east, focus: [0, 0.08, 0],
      cues: [
        .wait(1),
        .act("pats") { $0.walker.pats() },
        .untilStill, .wait(1),
      ]),
  ]
}
