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
  /// What stands in the room for her to look at.
  var interests: [(id: String, at: SIMD3<Float>, weight: Float)] = []
  /// What the room view looks at, and how many pixels a room unit takes in it.
  let focus: SIMD3<Float>
  var zoom: Float = 520
  let cues: [Cue]
}

private func facing(_ dx: Float, _ dz: Float) -> Float { atan2(-dx, -dz) }
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

  private static let room: [(id: String, at: SIMD3<Float>, weight: Float)] = [
    ("sill", [-0.5, 0.45, -0.6], 0.5), ("ball", [0.35, 0.02, 0.4], 0.3), ("bowl", [-0.45, 0, 0.35], 0.3),
  ]

  /// Where whoever watches is after turning the room by `angle` about her.
  private static func orbit(_ angle: Float) -> SIMD3<Float> {
    simd_quatf(angle: angle, axis: [0, 1, 0]).act([1, 0.82, 1])
  }

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

  static let all: [Scenario] = [
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
    // A minute and a half of her sitting alone, with what the app would bring her: the partner
    // coming in, whoever watches moving round her twice, a pet.
    Scenario(
      name: "idle", home: [0, 0, 0], yaw: facing(1, 0.4), interests: room, focus: [0, 0.08, 0],
      cues: [
        .wait(20),
        .act("partner") { $0.walker.behavior.perform(.listen) }, .wait(12),
        .each(1.5) { stage, t in stage.viewer = orbit(t / 1.5 * 1.2) },
        .wait(10),
        .each(1.5) { stage, t in stage.viewer = orbit(1.2 - t / 1.5 * 1.2) },
        .wait(12),
        .act("pet") { $0.walker.pet() }, .wait(30),
      ]),
    // Sent across the room and back, as the brain sends her: what she does before she gets up and
    // after she arrives.
    Scenario(
      name: "errand", home: [0.2, 0, -0.15], yaw: facing(1, 0.4), interests: room, focus: [0, 0.08, 0],
      cues: [
        .wait(4),
        go("to the rug", [.init(at: [-0.25, 0, 0.2])], rest: facing(0.6, 1)),
        .untilStill, .wait(5),
        .act("home") { $0.walker.go(to: nil) },
        .untilStill, .wait(4),
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
