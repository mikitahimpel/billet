import Foundation

/// The nightly touchpoint with no message in it: each of you puts your lamp out, and once both
/// are out the cat curls up.
public enum LightsOut {
  /// How long a goodnight lasts before the lamp comes on again by itself.
  public static let lasts: TimeInterval = 9 * 3600

  public enum Night: Equatable, Sendable {
    case awake
    /// This phone's lamp is out and the partner's is on.
    case waitingOnThem
    /// The partner's lamp is out and this phone's is on.
    case waitingOnMe
    /// Both lamps are out: the cat is curled up.
    case asleep
  }

  /// Whether a lamp put out at `goodnight` is still out at `now`.
  public static func isOut(since goodnight: Date?, now: Date) -> Bool {
    guard let goodnight else { return false }
    return now >= goodnight && now.timeIntervalSince(goodnight) < lasts
  }

  public static func night(mineOut: Bool, theirsOut: Bool) -> Night {
    switch (mineOut, theirsOut) {
    case (false, false): .awake
    case (true, false): .waitingOnThem
    case (false, true): .waitingOnMe
    case (true, true): .asleep
    }
  }
}
