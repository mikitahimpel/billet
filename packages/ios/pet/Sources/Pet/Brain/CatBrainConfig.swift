import Foundation

/// The constants of the cat's brain.
public struct CatBrainConfig: Hashable, Sendable {
  /// Decisions land on a grid this fine, in seconds, so both phones decide at the same instants.
  public var decisionStep = 0.25
  /// How often vitality and the needs are looked at again between steps, in seconds.
  public var checkEvery = 15.0
  /// The local hour each day of the brain starts from its canonical state. The cat is asleep
  /// then on almost every day, so the fresh start does not show.
  public var dayStartHour = 4.0
  /// How many days before today a cold start folds, for what the cat remembers.
  public var memoryDays = 2.0
  /// Sleep pressure above this makes the cat drowsy. The pressure already counts how tired it is.
  public var drowsyAbove = 0.55
  /// How long a pet, a game or a meal from either phone holds the cat, in seconds.
  public var petEcho = 4.0
  public var feedEcho = 7.0
  /// Recent groups remembered for boredom.
  public var recentCount = 12
  /// Transitions kept, for the debug overlay; tests keep them all.
  public var transitionCount = 10

  public init() {}

  public static let standard = CatBrainConfig()

  /// A partner unseen for this long is missed: the cat watches the window and waits by the door.
  public static let missingAfterHours = 12.0
}

/// A few bits of randomness from the seed and the moment alone, with no state, so a decision at
/// the same instant comes out the same on every phone however the fold got there.
public enum BrainDice {
  public static func roll(_ seed: UInt64, _ time: Double, _ salt: UInt64) -> Double {
    let tick = UInt64(bitPattern: Int64((time * 4).rounded(.down)))
    var random = SplitMix64(
      seed: seed ^ (tick &* 0x9E37_79B9_7F4A_7C15) ^ (salt &* 0xD6E8_FEB8_6659_FD93))
    return Double(random.next() >> 11) / Double(1 << 53)
  }

  static func range(_ range: ClosedRange<Double>, _ roll: Double) -> Double {
    range.lowerBound + (range.upperBound - range.lowerBound) * roll
  }
}
