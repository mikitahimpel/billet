import Foundation
import Wire

/// The items of one calendar day, titled "Today", "Yesterday" or the date.
public struct InboxDay: Sendable {
  public let day: Date
  public let title: String
  public let items: [ActivityItem]

  public static func group(
    _ items: [ActivityItem], now: Date = .now, calendar: Calendar = .current
  ) -> [InboxDay] {
    var days: [InboxDay] = []
    var current: (day: Date, title: String, items: [ActivityItem])?
    for item in items {
      let start = calendar.startOfDay(
        for: Date(timeIntervalSince1970: TimeInterval(item.at) / 1000))
      if current?.day == start {
        current?.items.append(item)
      } else {
        if let done = current {
          days.append(InboxDay(day: done.day, title: done.title, items: done.items))
        }
        current = (start, title(start, now: now, calendar: calendar), [item])
      }
    }
    if let done = current {
      days.append(InboxDay(day: done.day, title: done.title, items: done.items))
    }
    return days
  }

  static func title(_ day: Date, now: Date, calendar: Calendar) -> String {
    if calendar.isDate(day, inSameDayAs: now) { return "Today" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
      calendar.isDate(day, inSameDayAs: yesterday)
    {
      return "Yesterday"
    }
    let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
    return day.formatted(
      sameYear
        ? .dateTime.weekday(.wide).day().month(.wide) : .dateTime.day().month(.wide).year())
  }
}
