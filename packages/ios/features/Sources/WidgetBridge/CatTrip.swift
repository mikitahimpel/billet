import Foundation

/// The cat carrying a note: what a Live Activity shows from the moment it sets off until the note
/// is hung. Every field is plain data the app, an update or an ActivityKit push can all supply.
public enum CatTrip {
  public enum Phase: String, Codable, Hashable, Sendable {
    case onItsWay
    case hung
  }

  public struct Content: Codable, Hashable, Sendable {
    public var phase: Phase
    public var startedAt: Date
    /// When the cat is expected at the wall. The progress bar runs from `startedAt` to here on
    /// its own, so no update is needed while it walks.
    public var arrivesAt: Date
    /// True once a heart for the note has been asked for from the activity.
    public var hearted: Bool

    public init(phase: Phase, startedAt: Date, arrivesAt: Date, hearted: Bool = false) {
      self.phase = phase
      self.startedAt = startedAt
      self.arrivesAt = arrivesAt
      self.hearted = hearted
    }
  }

  /// The shortest and longest a trip is shown as taking.
  public static let durationRange: ClosedRange<TimeInterval> = 6...20

  /// How long the cat is expected to take: the scene's wait before the note appears, plus the walk.
  public static func expectedDuration(reveal: Duration) -> TimeInterval {
    let seconds =
      Double(reveal.components.seconds) + Double(reveal.components.attoseconds) / 1e18
    return min(max(seconds + 4, durationRange.lowerBound), durationRange.upperBound)
  }

  public static func begin(at now: Date, duration: TimeInterval) -> Content {
    Content(phase: .onItsWay, startedAt: now, arrivesAt: now.addingTimeInterval(duration))
  }

  /// The trip once the note is on the wall.
  public static func hung(_ content: Content, at now: Date) -> Content {
    var next = content
    next.phase = .hung
    next.arrivesAt = min(content.arrivesAt, now)
    return next
  }

  public static func hearted(_ content: Content) -> Content {
    var next = content
    next.hearted = true
    return next
  }

  /// How long the finished activity stays on the Lock Screen.
  public static let lingerAfterHung: TimeInterval = 10
}

#if os(iOS)
  import ActivityKit

  public struct CatTripAttributes: ActivityAttributes {
    public typealias ContentState = CatTrip.Content

    public var catName: String?

    public init(catName: String?) {
      self.catName = catName
    }
  }
#endif
