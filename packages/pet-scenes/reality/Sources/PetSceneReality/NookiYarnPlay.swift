import Foundation
import simd

/// Mochi's game with the yarn, as plain numbers: notice, watch, crouch, wiggle, chase, pounce, sit
/// on it proudly, then go back to bed. Nothing is counted and nothing is won.
///
/// Mochi's head is part of its body, so watching the ball turns the whole cat.
struct NookiYarnPlay: Equatable {
  enum Phase: Equatable {
    case resting
    case watching
    case crouching
    case wiggling
    case chasing
    case pouncing
    case proud
    case returning
  }

  /// The ball as the play needs it: where it is on the floor and how fast it is going.
  struct Ball: Equatable {
    var position: SIMD2<Float>
    var speed: Float
  }

  static let noticeSpeed: Float = 0.12
  static let ballHeight: Float = 0.13

  private static let settledSpeed: Float = 0.08
  private static let watchAtLeast = 0.7
  private static let watchAtMost = 3.0
  private static let crouchLength = 0.5
  private static let wiggleLength = 0.8
  private static let chaseAtMost = 6.0
  private static let pounceLength = 0.45
  private static let proudLength = 2.6
  private static let chaseSpeed: Float = 0.55
  private static let returnSpeed: Float = 0.8
  private static let pounceReach: Float = 0.26
  private static let wiggleSwing: Float = 0.16
  private static let hopsPerSecond = 2.6
  private static let bedRadius: Float = 0.2
  private static let turnRate: Float = 9

  let bed: SIMD3<Float>
  let floor: Float
  let restHeading: Float

  private(set) var phase = Phase.resting
  private(set) var position: SIMD2<Float>
  private var elapsed = 0.0
  private var heading: Float
  private var pounceFrom = SIMD2<Float>.zero
  private var ballAt = SIMD2<Float>.zero
  private var stillsOnly = false

  init(bed: SIMD3<Float>, floor: Float, restHeading: Float) {
    self.bed = bed
    self.floor = floor
    self.restHeading = restHeading
    position = SIMD2(bed.x, bed.z)
    heading = restHeading
  }

  var isPlaying: Bool { phase != .resting }
  /// True while Mochi is on the ball, which must hold still.
  var holdsBall: Bool { phase == .proud }

  /// Moves on by `delta` seconds. `canPlay` is false while something more important is on, and
  /// `reduceMotion` keeps Mochi in bed, awake and looking.
  mutating func step(ball: Ball, delta: Double, canPlay: Bool, reduceMotion: Bool) {
    ballAt = ball.position
    stillsOnly = reduceMotion
    elapsed += delta
    if !canPlay, phase != .resting, phase != .returning { enter(.returning) }
    switch phase {
    case .resting:
      if canPlay, ball.speed > Self.noticeSpeed { enter(.watching) }
    case .watching:
      turnToBall(delta)
      let settled = ball.speed < Self.settledSpeed && elapsed >= Self.watchAtLeast
      if settled || elapsed >= Self.watchAtMost {
        enter(reduceMotion ? .returning : .crouching)
      }
    case .crouching:
      turnToBall(delta)
      if elapsed >= Self.crouchLength { enter(.wiggling) }
    case .wiggling:
      turnToBall(delta)
      if elapsed >= Self.wiggleLength { enter(.chasing) }
    case .chasing:
      turnToBall(delta)
      travel(to: ball.position, speed: Self.chaseSpeed, delta: delta)
      if simd_distance(position, ball.position) <= Self.pounceReach {
        pounceFrom = position
        enter(.pouncing)
      } else if elapsed >= Self.chaseAtMost {
        enter(.returning)
      }
    case .pouncing:
      let share = Float(min(elapsed / Self.pounceLength, 1))
      position = mix(pounceFrom, ball.position, t: share)
      if elapsed >= Self.pounceLength { enter(.proud) }
    case .proud:
      if elapsed >= Self.proudLength { enter(.returning) }
    case .returning:
      let home = SIMD2(bed.x, bed.z)
      turn(towards: home, delta: delta)
      travel(to: home, speed: Self.returnSpeed, delta: delta)
      if simd_distance(position, home) < 0.01 {
        position = home
        heading = restHeading
        enter(.resting)
      }
    }
  }

  /// How the phase looks: the body's frame, and where Mochi stands while away from the bed.
  var pose: (frame: NookiFrame, spot: SIMD3<Float>) {
    var frame = NookiFrame(wake: 1, eyesOpen: true, heading: heading)
    var height = Self.groundHeight(position, bed: bed, floor: floor)
    let bounce = abs(sin(elapsed * Self.hopsPerSecond * .pi))
    switch phase {
    case .resting:
      frame = NookiFrame(heading: heading)
    case .watching:
      frame.mouth = 0.15
    case .crouching:
      frame.stretch = -Float(min(elapsed / Self.crouchLength, 1))
    case .wiggling:
      frame.stretch = -1
      frame.heading += Self.wiggleSwing * Float(sin(elapsed * 22))
    case .chasing, .returning:
      if !stillsOnly {
        frame.stepHeight = Float(bounce)
        frame.stretch = Float(bounce) * 2 - 1
      }
    case .pouncing:
      let share = min(elapsed / Self.pounceLength, 1)
      frame.stepHeight = NookiChoreography.arch(share) * 1.6
      frame.stretch = 1 - 2 * Float(share)
      height += Self.ballHeight * Float(share)
    case .proud:
      frame.mouth = 0.5
      frame.stretch = 0.5
      height += Self.ballHeight
    }
    return (frame, SIMD3(position.x, height, position.y))
  }

  private mutating func enter(_ next: Phase) {
    phase = next
    elapsed = 0
  }

  private mutating func turnToBall(_ delta: Double) {
    turn(towards: ballAt, delta: delta)
  }

  private mutating func turn(towards goal: SIMD2<Float>, delta: Double) {
    let offset = goal - position
    guard simd_length(offset) > 0.001 else { return }
    let wanted = atan2(-offset.x, -offset.y)
    let gap = remainder(wanted - heading, 2 * .pi)
    heading += gap * (stillsOnly ? 1 : 1 - exp(-Self.turnRate * Float(delta)))
  }

  private mutating func travel(to goal: SIMD2<Float>, speed: Float, delta: Double) {
    let gap = goal - position
    let distance = simd_length(gap)
    guard distance > 0 else { return }
    position += gap / distance * min(speed * Float(delta), distance)
  }

  private static func groundHeight(_ spot: SIMD2<Float>, bed: SIMD3<Float>, floor: Float) -> Float {
    let share = min(simd_distance(spot, SIMD2(bed.x, bed.z)) / bedRadius, 1)
    return bed.y + (floor - bed.y) * share
  }
}
