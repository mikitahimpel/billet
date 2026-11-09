import Foundation

/// The laser dot and the cat: she chases it when it is far or moving and pounces when it stops
/// close. Chasing and pouncing fill the play bar; full, the game is over.
public struct LaserPlay: Equatable, Sendable {
  public enum Cue: Equatable, Sendable {
    case chase(SIMD2<Double>)
    case pounce(SIMD2<Double>)
  }

  /// The cat's length in meters: distances scale with it.
  public let length: Double
  /// The floor the dot stays on, in the room's floor plane (x, z).
  public let floor: FloorArea

  public private(set) var dot: SIMD2<Double>?
  public private(set) var play: Double = 0
  public private(set) var pounces = 0
  /// Seconds the dot has been still.
  public private(set) var still: Double = 0

  public init(length: Double, floor: FloorArea) {
    self.length = length
    self.floor = floor
  }

  public var isDone: Bool { play >= 1 }

  /// Moves the dot to `point` (kept on the floor), or takes it away with nil.
  public mutating func aim(_ point: SIMD2<Double>?, dt: Double) {
    guard let point else {
      dot = nil
      still = 0
      return
    }
    let clamped = floor.clamp(point)
    let speed = dot.map { distance($0, clamped) / max(dt, 1e-3) } ?? .infinity
    still = speed < 0.03 ? still + dt : 0
    dot = clamped
  }

  /// What the cat at `cat` should do now, if free to; nil when the game is over or there's no dot.
  public func cue(cat: SIMD2<Double>) -> Cue? {
    guard let dot, !isDone else { return nil }
    let away = distance(cat, dot)
    if away > 0.62 * length { return .chase(dot) }
    if still > 0.35 { return .pounce(dot) }
    return nil
  }

  /// She ran `distance` meters after it.
  public mutating func ran(_ distance: Double) {
    play = min(1, play + max(0, distance) / (4 * length))
  }

  /// She landed a pounce.
  public mutating func pounced() {
    pounces += 1
    play = min(1, play + 0.2)
  }

  public static let cheers = ["Got it!", "Pounce!", "Again!"]
  public var cheer: String { Self.cheers[pounces % Self.cheers.count] }
}

/// A rectangle on the room's floor: `x` and `z` ranges, in meters.
public struct FloorArea: Equatable, Sendable {
  public var x: ClosedRange<Double>
  public var z: ClosedRange<Double>

  public init(x: ClosedRange<Double>, z: ClosedRange<Double>) {
    self.x = x
    self.z = z
  }

  public func clamp(_ point: SIMD2<Double>) -> SIMD2<Double> {
    SIMD2(
      Swift.min(Swift.max(point.x, x.lowerBound), x.upperBound),
      Swift.min(Swift.max(point.y, z.lowerBound), z.upperBound))
  }
}

func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
  let d = a - b
  return (d * d).sum().squareRoot()
}
