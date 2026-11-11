import Foundation
#if canImport(simd)
  import simd
#endif

/// A short trip from the cat's place and back, as a pure function of time. Positions are on the
/// floor plane as (x, z) in the room's metres; a heading is a yaw in radians, 0 facing -z, the
/// way the cats are made.
public struct CatTrip: Sendable {
  public enum Leg: Sendable {
    /// Walks (or runs, at a higher speed) in a straight line to `to`, in metres per second.
    case walk(to: SIMD2<Float>, speed: Float, action: CatAction = .walk)
    /// Stays put playing `action` for `seconds`, turned to face `facing` if given.
    case hold(CatAction, seconds: Double, facing: SIMD2<Float>? = nil)
  }

  public struct Pose: Equatable, Sendable {
    public var spot: SIMD2<Float>
    public var heading: Float
    public var action: CatAction
    /// Metres per second across the floor, 0 when holding.
    public var speed: Float
    /// Which leg is playing, and how far into it, from 0 to 1.
    public var leg: Int
    public var progress: Double
    public var isDone: Bool

    public init(
      spot: SIMD2<Float>, heading: Float, action: CatAction, speed: Float, leg: Int,
      progress: Double, isDone: Bool
    ) {
      self.spot = spot
      self.heading = heading
      self.action = action
      self.speed = speed
      self.leg = leg
      self.progress = progress
      self.isDone = isDone
    }
  }

  /// How long a turn on the spot takes before a walk sets off.
  public static let turnLength = 0.3

  private struct Span {
    var start: Double
    var length: Double
    var from: SIMD2<Float>
    var to: SIMD2<Float>
    var headingFrom: Float
    var heading: Float
    var action: CatAction
    var speed: Float
  }

  public let startedAt: Double
  private let spans: [Span]
  private let home: SIMD2<Float>
  private let homeHeading: Float

  public init(from start: SIMD2<Float>, heading: Float, legs: [Leg], at now: Double) {
    startedAt = now
    home = start
    homeHeading = heading
    var spans: [Span] = []
    var at = start
    var facing = heading
    var clock = now
    for leg in legs {
      switch leg {
      case .walk(let to, let speed, let action):
        let distance = simd_distance(at, to)
        let towards = distance > 0.001 ? Self.heading(from: at, to: to) : facing
        let length = Double(distance / max(speed, 0.01)) + Self.turnLength
        spans.append(
          Span(
            start: clock, length: length, from: at, to: to, headingFrom: facing, heading: towards,
            action: action, speed: speed))
        at = to
        facing = towards
        clock += length
      case .hold(let action, let seconds, let target):
        let towards = target.map { Self.heading(from: at, to: $0) } ?? facing
        spans.append(
          Span(
            start: clock, length: seconds, from: at, to: at, headingFrom: facing,
            heading: towards, action: action, speed: 0))
        facing = towards
        clock += seconds
      }
    }
    self.spans = spans
  }

  public var endsAt: Double { spans.last.map { $0.start + $0.length } ?? startedAt }

  public func pose(at now: Double) -> Pose {
    guard let index = spans.lastIndex(where: { $0.start <= now }) ?? (spans.isEmpty ? nil : 0)
    else {
      return Pose(
        spot: home, heading: homeHeading, action: .sit, speed: 0, leg: 0, progress: 1,
        isDone: true)
    }
    let span = spans[index]
    let into = min(max(now - span.start, 0), span.length)
    let progress = span.length > 0 ? into / span.length : 1
    let turned = Float(min(into / Self.turnLength, 1))
    let heading = Self.blend(span.headingFrom, span.heading, turned)
    if span.speed > 0 {
      let moving = max(into - Self.turnLength, 0) / max(span.length - Self.turnLength, 0.001)
      let spot = span.from + (span.to - span.from) * Float(min(moving, 1))
      return Pose(
        spot: spot, heading: heading, action: into < Self.turnLength ? .idle : span.action,
        speed: into < Self.turnLength ? 0 : span.speed, leg: index, progress: progress,
        isDone: now >= endsAt)
    }
    return Pose(
      spot: span.from, heading: heading, action: span.action, speed: 0, leg: index,
      progress: progress, isDone: now >= endsAt)
  }

  public static func heading(from a: SIMD2<Float>, to b: SIMD2<Float>) -> Float {
    let offset = b - a
    return atan2(-offset.x, -offset.y)
  }

  /// Turns the short way round from `a` to `b`.
  static func blend(_ a: Float, _ b: Float, _ t: Float) -> Float {
    let turn = remainder(b - a, 2 * .pi)
    return a + turn * t
  }

  /// The spot `distance` from `from` towards `to`, but no closer to `to` than `keep`.
  public static func towards(
    _ to: SIMD2<Float>, from: SIMD2<Float>, upTo distance: Float, keep: Float = 0
  ) -> SIMD2<Float> {
    let offset = to - from
    let length = simd_length(offset)
    guard length > 0.001 else { return from }
    let travel = max(min(distance, length - keep), 0)
    return from + offset / length * travel
  }
}
