import Foundation
import GamesInterface

/// A kitchen scale with the cat's bowl: TARE zeroes whatever is on the platform, and the display
/// shows whole grams of the load less the tare, negative once a tared bowl comes off.
public struct KibbleScale: Equatable, Sendable {
  public static let bowlGrams: Double = 118
  /// One kibble, as the pinch moves them.
  public static let kibbleGrams: Double = 0.5

  public private(set) var bowlOnScale = false
  public private(set) var tare: Double = 0
  /// What is in the bowl, wherever the bowl is.
  public private(set) var food: Double = 0

  public init() {}

  /// What lies on the platform.
  public var load: Double { bowlOnScale ? Self.bowlGrams + food : 0 }

  /// The display, in whole grams.
  public var reading: Int { Int((load - tare).rounded()) }

  /// Whether the display reads the food alone: the bowl is on and was tared empty.
  public var isTared: Bool { tare > 0 && abs(tare - Self.bowlGrams) < 0.01 }

  public mutating func putBowl(onScale: Bool) { bowlOnScale = onScale }

  public mutating func pressTare() { tare = load }

  /// Pours `grams` in, or takes them out when negative; the bowl never holds less than nothing.
  public mutating func add(_ grams: Double) { food = max(0, food + grams) }

  /// Starts a new meal with an empty bowl off the scale.
  public mutating func reset() { self = KibbleScale() }
}

/// How much the cat needs, from how full she is, and whether a bowl is close enough to it to serve.
public struct FeedTask: Equatable, Sendable {
  public enum Check: Equatable, Sendable {
    /// Close enough; `perfect` when on the gram.
    case ready(perfect: Bool)
    case tooMuch(grams: Int)
    case tooLittle(grams: Int)
  }

  public static let grams = FeedPenalty.portions

  public let target: Int

  public init(target: Int) {
    self.target = FeedPenalty.portion(target)
  }

  /// The portion for a cat this `full` (0...1): the emptier she is, the more she needs.
  public init(full: Double) {
    let empty = 1 - min(max(full, 0), 1)
    self.init(
      target: Int((Double(Self.grams.lowerBound) + empty * Double(Self.grams.count - 1)).rounded()))
  }

  /// Grams either side of the target that still count: 2, or 5 % of a big portion.
  public var tolerance: Int { FeedPenalty.tolerance(target: target) }

  /// The most the bag pours: past the zone, into the overfeed.
  public var hardCap: Int { FeedPenalty.hardCap(target: target) }

  public func check(food: Double) -> Check {
    let grams = Int(food.rounded())
    let diff = grams - target
    if abs(diff) <= tolerance { return .ready(perfect: diff == 0) }
    return diff > 0 ? .tooMuch(grams: diff) : .tooLittle(grams: -diff)
  }

  /// What the card says when the bowl isn't ready yet, or nil when it is.
  public func advice(food: Double) -> String? {
    switch check(food: food) {
    case .ready: nil
    case .tooMuch(let grams): "\(grams) g too much: take some out"
    case .tooLittle(let grams): "\(grams) g to go"
    }
  }
}

/// The four ways kibble goes into the bowl, and the one it comes back out.
public enum KibblePour {
  /// Grams a second from the bag tipped `angle` radians: nothing until the kibble reaches the
  /// mouth, then more the further it goes.
  public static func flow(angle: Double) -> Double {
    20 * smoothstep(angle, 0.6, 1.9)
  }

  /// A clump of 5-8 g when the bag is tipped fast and far, at most every 2.5 s.
  public static func clump(
    turnRate: Double, angle: Double, sinceLast: Double, using rng: inout some RandomNumberGenerator
  ) -> Double? {
    guard turnRate > 4.5, angle > 1.1, sinceLast > 2.5 else { return nil }
    return Double.random(in: 5...8, using: &rng)
  }

  /// One scoop: 8-14 g, never quite the same.
  public static func scoop(using rng: inout some RandomNumberGenerator) -> Double {
    Double.random(in: 8...14, using: &rng)
  }

  public static let pinch = KibbleScale.kibbleGrams

  /// A shake of `strength` (0...1) loosens one to three kibbles.
  public static func shake(strength: Double, using rng: inout some RandomNumberGenerator) -> Double
  {
    let kibbles = 1 + Int(Double.random(in: 0..<1.6, using: &rng) + min(max(strength, 0), 1) * 2.4)
    return Double(kibbles) * KibbleScale.kibbleGrams
  }

  /// Grams a second poured back from the bowl tipped `tilt` radians over the bag.
  public static func back(tilt: Double) -> Double {
    12 * smoothstep(tilt, 0.6, 1.5)
  }
}

func smoothstep(_ x: Double, _ edge0: Double, _ edge1: Double) -> Double {
  let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
  return t * t * (3 - 2 * t)
}

/// The kibble that bounced out of an overfull bowl and lies on the mat, until it is swept up.
public struct FeedMess: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case tidy, messy
  }

  /// Pieces on the mat now.
  public private(set) var pieces = 0
  /// Whether any piece ever left the bowl.
  public private(set) var spilled = false

  public init() {}

  public var phase: Phase { pieces > 0 ? .messy : .tidy }
  public var isSpotless: Bool { spilled && pieces == 0 }

  /// Whether the `poured`th piece of a bowl whose zone ends at `zoneEnd` grams bounces out: every second one
  /// past the zone. The grams still count for the meal, so the overfeed table is untouched.
  public static func spills(poured: Int, zoneEnd: Int) -> Bool {
    poured > zoneEnd && (poured - zoneEnd).isMultiple(of: 2)
  }

  public mutating func spill() {
    pieces += 1
    spilled = true
  }

  /// A sweep takes up `count` pieces.
  public mutating func sweep(_ count: Int = 1) { pieces = max(0, pieces - max(count, 0)) }
}
