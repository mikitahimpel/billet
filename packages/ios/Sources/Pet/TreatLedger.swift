import Foundation

/// Who gave a treat on which day, and what that means for the cat and the streak.
///
/// The room keeps the same table, so two phones that have both read it agree on every answer.
public struct TreatLedger: Hashable, Sendable {
  /// Where the pair stands on one day's treat.
  public enum Status: Hashable, Sendable {
    case neither
    /// This device gave; the partner has not.
    case waitingOnPartner
    /// The partner gave; this device has not.
    case waitingOnMe
    /// Both gave, so the cat gets the treat.
    case fed
  }

  public private(set) var days: [String: Set<String>]

  public init(days: [String: Set<String>] = [:]) {
    self.days = days
  }

  /// Records `device`'s treat on `day`. A second treat the same day changes nothing.
  public mutating func give(device: String, on day: String) {
    days[day, default: []].insert(device)
  }

  /// Adds what the room knows. Merging never removes a treat given here and not yet acknowledged.
  public mutating func merge(_ other: [String: Set<String>]) {
    for (day, devices) in other {
      days[day, default: []].formUnion(devices)
    }
  }

  public func status(for device: String, on day: String) -> Status {
    let given = days[day] ?? []
    let mine = given.contains(device)
    let theirs = given.contains { $0 != device }
    switch (mine, theirs) {
    case (true, true): return .fed
    case (true, false): return .waitingOnPartner
    case (false, true): return .waitingOnMe
    case (false, false): return .neither
    }
  }

  /// Consecutive days on which both gave a treat.
  ///
  /// Today counts once both have given. Until then it is still open, so the run that ended
  /// yesterday stands. A day with a missing treat ends the run, and the count starts again at zero.
  public func streak(today: String, calendar: Calendar) -> Int {
    var count = 0
    var day: String? = today
    if !isShared(today) { day = TreatDay.previous(today, calendar: calendar) }
    while let current = day, isShared(current) {
      count += 1
      day = TreatDay.previous(current, calendar: calendar)
    }
    return count
  }

  private func isShared(_ day: String) -> Bool {
    (days[day] ?? []).count >= 2
  }
}
