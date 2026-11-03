import Foundation

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

/// A finger held still near the edge of the screen, as the cat sees it. Only a finger that has
/// rested for ``dwell`` within ``radius`` points counts, so a quick swipe to turn the room never
/// gets batted at. Feed it every point the finger moves to, and ``lifted()`` when it leaves. A
/// rest lapses after ``hold``, so a touch whose end never arrives does not keep the cat batting.
public struct CatFingerRest: Equatable, Sendable {
  public static let radius = 8.0
  public static let dwell = 0.35
  public static let hold = 6.0

  private var anchor: (x: Double, y: Double)?
  private var settled = 0.0
  private var since = 0.0

  public init() {}

  public mutating func moved(toX x: Double, y: Double, at t: Double) {
    if let anchor, hypot(x - anchor.x, y - anchor.y) <= Self.radius { return }
    anchor = (x, y)
    settled = t
    since = t
  }

  public mutating func lifted() { anchor = nil }

  /// Starts the wait again, after the cat has batted, so one rest is one bat.
  public mutating func restart(at t: Double) { since = t }

  /// Where the finger rests at `t`, or nil while it is moving or up.
  public func resting(at t: Double) -> (x: Double, y: Double)? {
    guard let anchor, t - since >= Self.dwell, t - settled <= Self.hold else { return nil }
    return anchor
  }

  public static func == (a: CatFingerRest, b: CatFingerRest) -> Bool {
    a.anchor?.x == b.anchor?.x && a.anchor?.y == b.anchor?.y && a.settled == b.settled
      && a.since == b.since
  }
}
