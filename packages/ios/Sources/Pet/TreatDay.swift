import Foundation

/// Calendar days as the room stores them: `yyyy-MM-dd` in the giving device's own calendar.
public enum TreatDay {
  /// The day `date` falls on in `calendar`.
  public static func key(for date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  /// `date` as an ISO time with the calendar's UTC offset, so the room reads the local day from it.
  public static func timestamp(for date: Date, calendar: Calendar) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = calendar.timeZone
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  /// The day before `key`, or nil when `key` is not a valid day.
  public static func previous(_ key: String, calendar: Calendar) -> String? {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3,
      let date = calendar.date(
        from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
      let before = calendar.date(byAdding: .day, value: -1, to: date)
    else { return nil }
    return Self.key(for: before, calendar: calendar)
  }
}
