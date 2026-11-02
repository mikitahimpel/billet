import Foundation

/// A small scene the cat can play on its own, each switched on in Labs. All cats play every
/// moment; a cat without a clip for a move plays the nearest one it has.
public enum CatMoment: String, CaseIterable, Codable, Hashable, Sendable {
  /// A note arrives: the cat carries it in its mouth to the wall or the glass and tapes it up.
  case carriesNote
  /// Petting purrs under the finger with small floating hearts; a long pet rolls it onto its back.
  case purrs
  /// A finger near the edge of the screen catches its eye, and it bats at it.
  case batsAtFinger
  /// Back after hours away, it runs up to the camera and headbutts it.
  case greets
  /// Now and then it chases the yarn, or a dot of light from the lamp, on its own.
  case chases
}

/// When the cat greets: after this long without the room on screen.
public enum CatGreeting {
  public static let awayLong: TimeInterval = 3 * 60 * 60

  public static func isDue(lastSeen: Date?, now: Date) -> Bool {
    guard let lastSeen else { return false }
    return now.timeIntervalSince(lastSeen) >= awayLong
  }
}

/// When a finger counts as near the edge: within this many points of the left or right side.
public enum CatEdge {
  public static let reach: Double = 64

  public static func isNearEdge(x: Double, width: Double) -> Bool {
    width > reach * 2 && (x < reach || x > width - reach)
  }
}

/// When the cat chases on its own: at a random gap in this range, counted while it is idle.
public struct CatPlayClock: Sendable {
  public static let gap = 45.0...90.0
  /// The first chase comes sooner, so someone trying the switch sees one.
  public static let firstGap = 8.0...14.0

  private var random: SplitMix64
  private var due: Double?

  public init(seed: UInt64 = 1) { random = SplitMix64(seed: seed) }

  /// Whether a chase is due at `now`. Asking moves the clock on to the next one when it is.
  public mutating func isDue(at now: Double) -> Bool {
    guard let due else {
      self.due = now + random.next(in: Self.firstGap)
      return false
    }
    guard now >= due else { return false }
    self.due = now + random.next(in: Self.gap)
    return true
  }

  /// Puts the next chase a full gap away, after something else kept the cat busy.
  public mutating func postpone(from now: Double) {
    due = max(due ?? now, now + random.next(in: Self.firstGap))
  }
}
