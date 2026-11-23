import Foundation
import simd

/// A fixed set of moves, the same every run, played from sitting at `home` facing `yaw`.
struct Scenario {
  enum Cue {
    case act(String, (Stage) -> Void)
    case wait(Float)
    /// Until she has finished what she was told to do.
    case untilStill
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

  static let all: [Scenario] = [
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
