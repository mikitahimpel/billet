import Foundation
import Wire

/// One partner's latest mood as the phone keeps it, in the App Group file the header and the
/// widgets read.
public struct MoodCheckIn: Codable, Hashable, Sendable {
  public var mood: CheckInMood
  public var date: Date
  /// A few words with the mood, at most `noteLimit` UTF-16 units, as the server keeps it.
  public var note: String?

  public static let noteLimit = 80

  public init(mood: CheckInMood, date: Date, note: String? = nil) {
    self.mood = mood
    self.date = date
    self.note = note
  }

  /// Trimmed, cut to the limit, and nil when nothing is left.
  public static func clean(_ note: String?) -> String? {
    guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    var cut = trimmed
    while cut.utf16.count > noteLimit { cut.removeLast() }
    return cut
  }

  /// From the last day: what the header and the widgets show.
  public func isFresh(at now: Date = .now) -> Bool { date > now.addingTimeInterval(-86_400) }

  /// Puts `check` in `latest` unless a later one is already there, such as one set on this phone
  /// before the server heard of it; `replacing` puts it anyway, as the server's copy of the one this
  /// phone just sent. Returns whether it was put.
  @discardableResult
  public static func take(
    _ check: MoodCheckIn, for partner: String, into latest: inout [String: MoodCheckIn],
    replacing: Bool = false
  ) -> Bool {
    if !replacing, let current = latest[partner], current.date > check.date { return false }
    latest[partner] = check
    return true
  }
}

/// The couple's latest check-ins by partner monogram.
public protocol MoodChecking: AnyObject {
  var latest: [String: MoodCheckIn] { get }
  /// See ``MoodCheckIn/take(_:for:into:replacing:)``.
  @discardableResult
  func take(_ check: MoodCheckIn, for partner: String, replacing: Bool) -> Bool
}
