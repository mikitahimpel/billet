import FeatureInbox
import Foundation

/// One page of a week's notes, from the notes already kept on this device.
public struct SundayPost: Equatable, Sendable {
  /// Most notes that fit on a page.
  public static let capacity = 6

  public let weekStart: Date
  public let weekEnd: Date
  /// The notes on the page, oldest first.
  public let notes: [NoteRecord]
  public let sent: Int
  public let received: Int

  /// The page Mochi brings on or after a Sunday: the Monday-to-Sunday week that Sunday ends. On
  /// any other day it is the last finished week, unless `preview` asks for the week so far.
  /// Returns nil when that week had no notes.
  public static func page(
    from notes: [NoteRecord], now: Date, calendar: Calendar, preview: Bool = false
  ) -> SundayPost? {
    var calendar = calendar
    calendar.firstWeekday = 2
    guard let week = weekToShow(now: now, calendar: calendar, preview: preview) else { return nil }
    let inWeek = notes.filter { week.contains($0.date) }.sorted { $0.date < $1.date }
    guard !inWeek.isEmpty else { return nil }
    let chosen = Array(inWeek.suffix(capacity))
    return SundayPost(
      weekStart: week.start,
      weekEnd: calendar.date(byAdding: .day, value: 6, to: week.start) ?? week.end,
      notes: chosen,
      sent: inWeek.filter { $0.direction == .sent }.count,
      received: inWeek.filter { $0.direction == .received }.count)
  }

  /// True on a Sunday, when the page is the week just ending.
  public static func isSunday(_ now: Date, calendar: Calendar) -> Bool {
    calendar.component(.weekday, from: now) == 1
  }

  private static func weekToShow(now: Date, calendar: Calendar, preview: Bool) -> DateInterval? {
    if preview || isSunday(now, calendar: calendar) {
      return calendar.dateInterval(of: .weekOfYear, for: now)
    }
    guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now) else {
      return nil
    }
    return calendar.dateInterval(of: .weekOfYear, for: lastWeek)
  }
}
