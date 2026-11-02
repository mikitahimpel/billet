import Foundation
import Observation

/// The day the two of you next meet, set on this phone.
public struct NextVisit: Codable, Equatable, Sendable {
  /// How full the suitcase gets.
  public static let compartments = 5

  /// When the day was chosen, as the start of that day.
  public let setOn: Date
  /// The day itself, as the start of that day.
  public let day: Date

  public init(day: Date, setOn: Date, calendar: Calendar = .current) {
    self.day = calendar.startOfDay(for: day)
    self.setOn = calendar.startOfDay(for: setOn)
  }

  /// Whole days from today to the visit: 0 on the day, negative after it.
  public func daysLeft(now: Date, calendar: Calendar) -> Int {
    calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 0
  }

  /// How many of the suitcase's compartments are packed: none when the day is set, all of them on
  /// the day, in proportion to the time that has passed in between.
  public func packed(now: Date, calendar: Calendar) -> Int {
    let left = daysLeft(now: now, calendar: calendar)
    if left <= 0 { return Self.compartments }
    let total = max(1, calendar.dateComponents([.day], from: setOn, to: day).day ?? 1)
    let elapsed = min(total, max(0, total - left))
    return min(
      Self.compartments,
      Int((Double(elapsed) / Double(total) * Double(Self.compartments)).rounded(.down)))
  }

  /// True until the day after the visit, when the suitcase is put away.
  public func isShown(now: Date, calendar: Calendar) -> Bool {
    daysLeft(now: now, calendar: calendar) >= 0
  }
}

/// The next visit, kept in `defaults`.
@MainActor
@Observable
public final class NextVisitStore {
  public private(set) var visit: NextVisit?

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let key: String

  public init(defaults: UserDefaults = .standard, key: String = "labs.nextVisit") {
    self.defaults = defaults
    self.key = key
    visit = defaults.data(forKey: key).flatMap {
      try? JSONDecoder().decode(NextVisit.self, from: $0)
    }
  }

  public func set(day: Date, now: Date, calendar: Calendar) {
    visit = NextVisit(day: day, setOn: now, calendar: calendar)
    defaults.set(try? JSONEncoder().encode(visit), forKey: key)
  }

  public func clear() {
    visit = nil
    defaults.removeObject(forKey: key)
  }
}
