import Foundation
import simd

/// The cat going after a toy that moves: it watches, stalks or runs closer, wiggles its rump,
/// pounces, and either bats what it caught, carries it back, or tries again. The room moves the
/// toy and tells the pursuit where it is each frame; the pursuit says where the cat is and what
/// it plays, as a ``CatTrip/Pose``, so a room shows it the way it shows a trip.
///
/// Positions are on the floor plane, as (x, z), in the room's units; `length` is the cat's.
public struct CatPursuit: Sendable {
  public enum Phase: Hashable, Sendable {
    case watch
    case stalk
    case wiggle
    case pounce
    /// Got it: a bat at a feather or a dot, a grab at a ball.
    case caught
    /// Bringing a ball back to where it was thrown from.
    case carry
    case rest
    case done
  }

  /// What happened this step, for the room to tell the play machine or drop the toy.
  public enum Event: Hashable, Sendable {
    case caught
    /// The toy carried back was let go of here.
    case dropped(SIMD2<Float>)
  }

  public let toy: CatToy
  public let length: Float
  public private(set) var phase: Phase = .watch
  public private(set) var spot: SIMD2<Float>
  public private(set) var heading: Float
  public private(set) var catches = 0
  /// Where a caught ball is carried, or nil when this one is not brought back.
  public var fetchTo: SIMD2<Float>?
  private var phaseStart: Double
  private var lastMoved: Double
  private var pounceFrom = SIMD2<Float>.zero
  private var pounceTo = SIMD2<Float>.zero
  private var speed: Float = 0

  public static let watchLength = 0.6
  public static let wiggleLength = 0.65
  public static let pounceLength = 0.42
  public static let caughtLength = 1.0
  public static let restLength = 1.1
  /// How long a toy can lie still before the cat loses interest.
  public static let boredAfter = 3.0
  /// How fast the cat turns, in radians a second.
  static let turnRate: Float = 7

  /// Walking pace and running pace, in cat lengths a second.
  static let stalkPace: Float = 0.45
  static let runPace: Float = 2.2
  /// A toy faster than this many cat lengths a second is run after rather than stalked.
  static let fleeing: Float = 1.2

  /// From this far, in cat lengths, it stops to wiggle and pounce.
  static let pounceReach: Float = 1.0
  /// Within this far, in cat lengths, at the end of a pounce, it has the toy.
  static let catchReach: Float = 0.5

  public init(
    toy: CatToy, from spot: SIMD2<Float>, heading: Float, length: Float,
    fetchTo: SIMD2<Float>? = nil, at now: Double
  ) {
    self.toy = toy
    self.spot = spot
    self.heading = heading
    self.length = max(length, 0.001)
    self.fetchTo = fetchTo
    phaseStart = now
    lastMoved = now
  }

  public var isDone: Bool { phase == .done }
  /// True while the ball rides in the cat's mouth.
  public var holdsToy: Bool { phase == .carry }

  /// The cat's place and move now, for the room to show.
  public var pose: CatTrip.Pose {
    CatTrip.Pose(
      spot: spot, heading: heading, action: action, speed: speed, leg: 0, progress: 0,
      isDone: isDone)
  }

  public var action: CatAction {
    switch phase {
    case .watch: .look
    case .stalk, .carry: speed > 0.001 ? .walk : .crouchWiggle
    case .wiggle: .crouchWiggle
    case .pounce: .pounce
    case .caught: toy.isThrown ? .grab : .bat
    case .rest: .happy
    case .done: .sit
    }
  }

  /// Moves the cat on by `delta` seconds towards a toy now at `target`, moving at `targetSpeed`
  /// in room units a second. Pass `target: nil` once the toy is gone, and the cat gives up.
  public mutating func step(
    target: SIMD2<Float>?, targetSpeed: Float, at now: Double, delta: Double
  ) -> Event? {
    guard phase != .done else { return nil }
    guard let target else {
      enter(.done, at: now)
      return nil
    }
    let moving = targetSpeed > length * 0.15
    if moving { lastMoved = now }
    let since = now - phaseStart
    let distance = simd_distance(spot, target)
    let step = Float(delta)
    speed = 0
    switch phase {
    case .watch:
      turn(towards: target, step)
      if since >= Self.watchLength { enter(.stalk, at: now) }
    case .stalk:
      turn(towards: target, step)
      if distance <= length * Self.pounceReach {
        enter(.wiggle, at: now)
      } else if now - lastMoved > Self.boredAfter {
        enter(.done, at: now)
      } else {
        let pace = targetSpeed > length * Self.fleeing ? Self.runPace : Self.stalkPace
        travel(towards: target, speed: length * pace, keep: length * 0.3, step)
      }
    case .wiggle:
      turn(towards: target, step)
      if distance > length * Self.pounceReach * 1.7 {
        enter(.stalk, at: now)
      } else if since >= Self.wiggleLength {
        pounceFrom = spot
        let lead = target - spot
        pounceTo = spot + lead * max(0, 1 - length * 0.25 / max(simd_length(lead), 0.001))
        enter(.pounce, at: now)
      }
    case .pounce:
      let t = Float(min(since / Self.pounceLength, 1))
      let eased = t * t * (3 - 2 * t)
      let next = pounceFrom + (pounceTo - pounceFrom) * eased
      speed = simd_distance(next, spot) / max(step, 0.001)
      spot = next
      if t >= 1 {
        if simd_distance(spot, target) <= length * Self.catchReach {
          catches += 1
          enter(.caught, at: now)
          return .caught
        }
        enter(.stalk, at: now)
      }
    case .caught:
      if since >= Self.caughtLength {
        enter(fetchTo != nil && toy.isThrown ? .carry : .rest, at: now)
      }
    case .carry:
      guard let fetchTo else {
        enter(.rest, at: now)
        return nil
      }
      turn(towards: fetchTo, step)
      if simd_distance(spot, fetchTo) <= length * 0.05 {
        self.fetchTo = nil
        enter(.rest, at: now)
        return .dropped(spot)
      }
      travel(towards: fetchTo, speed: length * 0.9, keep: 0, step)
    case .rest:
      turn(towards: target, step)
      if since >= Self.restLength {
        // A toy still being moved gets another go; one left lying is left.
        enter(now - lastMoved < Self.restLength ? .watch : .done, at: now)
      }
    case .done:
      break
    }
    return nil
  }

  private mutating func enter(_ next: Phase, at now: Double) {
    phase = next
    phaseStart = now
    if next == .done { speed = 0 }
  }

  private mutating func turn(towards goal: SIMD2<Float>, _ step: Float) {
    guard simd_distance(goal, spot) > 0.0001 else { return }
    let want = CatTrip.heading(from: spot, to: goal)
    let turn = remainder(want - heading, 2 * .pi)
    let most = Self.turnRate * step
    heading += min(max(turn, -most), most)
  }

  private mutating func travel(
    towards goal: SIMD2<Float>, speed: Float, keep: Float, _ step: Float
  ) {
    let next = CatTrip.towards(goal, from: spot, upTo: speed * step, keep: keep)
    self.speed = simd_distance(next, spot) / max(step, 0.001)
    spot = next
  }
}

/// A thrown toy rolling across the cat's floor: it slows, and bounces off the edges.
public struct RollingToy: Sendable {
  public var position: SIMD2<Float>
  public var velocity: SIMD2<Float>
  /// The floor's corners, or nil for no edges.
  public var bounds: (min: SIMD2<Float>, max: SIMD2<Float>)?
  /// How much of its speed it keeps each second.
  public var grip: Float

  public init(
    at position: SIMD2<Float>, bounds: (min: SIMD2<Float>, max: SIMD2<Float>)?, grip: Float
  ) {
    self.position = position
    velocity = .zero
    self.bounds = bounds
    self.grip = grip
  }

  public var speed: Float { simd_length(velocity) }

  public mutating func step(_ delta: Double) {
    let step = Float(delta)
    position += velocity * step
    velocity *= pow(grip, step)
    if simd_length(velocity) < 0.01 { velocity = .zero }
    guard let bounds else { return }
    for axis in 0..<2 {
      if position[axis] < bounds.min[axis] {
        position[axis] = bounds.min[axis]
        velocity[axis] = abs(velocity[axis]) * 0.6
      } else if position[axis] > bounds.max[axis] {
        position[axis] = bounds.max[axis]
        velocity[axis] = -abs(velocity[axis]) * 0.6
      }
    }
  }
}
