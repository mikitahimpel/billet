/// One lesson: a few rounds of the same small timing game, each trick with its own rhythm. A cue
/// runs from 0 to 1 over a round's seconds; a tap inside each of its windows, in order, is a hit.
public struct LessonPlan: Equatable, Hashable, Sendable {
  public struct Round: Equatable, Hashable, Sendable {
    public let seconds: Double
    /// Parts of the cue, each from 0 to 1, in order and apart.
    public let windows: [ClosedRange<Double>]

    public init(seconds: Double, windows: [ClosedRange<Double>]) {
      self.seconds = seconds
      self.windows = windows
    }

    /// Whether `taps` so far can still be a hit, and whether they already are one.
    public func judge(_ taps: [Double]) -> Verdict {
      guard taps.count <= windows.count else { return .miss }
      for (tap, window) in zip(taps, windows) where !window.contains(tap) { return .miss }
      return taps.count == windows.count ? .hit : .open
    }
  }

  public enum Verdict: Equatable, Sendable {
    case open
    case hit
    case miss
  }

  public static let rounds = 5
  public static let needed = 3

  public let trick: SchoolTrick
  /// The star this lesson earns, 1 to 3. A higher star narrows the windows.
  public let star: Int
  public let rounds: [Round]

  public var needed: Int { Self.needed }

  /// `seed` moves the windows of the tricks whose moment is a surprise.
  public init(trick: SchoolTrick, star: Int, seed: UInt64 = 0) {
    self.trick = trick
    self.star = star
    let narrow = 1 - 0.2 * Double(min(max(star, 1), 3) - 1)
    rounds = (0..<Self.rounds).map { round in
      switch trick {
      case .bow:
        // Patience: a slow cue with its moment at the end.
        return Round(seconds: 3.2, windows: [Self.window(at: 0.84, width: 0.2 * narrow)])
      case .jump:
        // One sharp moment in a quick cue.
        return Round(seconds: 1.6, windows: [Self.window(at: 0.6, width: 0.16 * narrow)])
      case .spin:
        // Two beats, one for each half of the turn.
        return Round(
          seconds: 2.4,
          windows: [
            Self.window(at: 0.35, width: 0.18 * narrow),
            Self.window(at: 0.75, width: 0.18 * narrow),
          ])
      case .highFive:
        // The paw comes up when it comes up.
        let spot = 0.3 + 0.5 * Self.unit(seed, round)
        return Round(seconds: 2.2, windows: [Self.window(at: spot, width: 0.18 * narrow)])
      }
    }
  }

  private static func window(at centre: Double, width: Double) -> ClosedRange<Double> {
    max(0, centre - width / 2)...min(1, centre + width / 2)
  }

  /// From 0 up to 1, the same for the same seed and round.
  private static func unit(_ seed: UInt64, _ round: Int) -> Double {
    var x = seed &+ UInt64(round + 1) &* 0x9E37_79B9_7F4A_7C15
    x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
    x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
    x ^= x >> 31
    return Double(x >> 11) / Double(1 << 53)
  }
}
