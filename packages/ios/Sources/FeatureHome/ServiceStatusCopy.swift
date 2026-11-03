import Foundation
import Wire

/// The words the status screens show, worked out from the service's status.
enum ServiceStatusCopy {
  /// Said when the service gives maintenance no message of its own.
  static let restingMessage = "billet is resting for a little while."

  /// The app's own string for the message's key when it has one, otherwise the service's text.
  static func text(_ message: StatusMessage, strings: (String) -> String?) -> String {
    strings(message.key) ?? message.text
  }

  /// What the maintenance screen says, or the resting line when the service says nothing.
  static func maintenanceMessage(
    _ maintenance: MaintenanceStatus, strings: (String) -> String?
  ) -> String {
    maintenance.message.map { text($0, strings: strings) } ?? restingMessage
  }

  /// "Back around 22:30" in `timeZone`, with the weekday when it is not today there. `nil` with
  /// no `until`, or once it has passed: a time already gone promises nothing.
  static func backAround(
    _ until: Date?, now: Date, timeZone: TimeZone, locale: Locale
  ) -> String? {
    guard let until, until > now else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.locale = locale
    let time = Date.FormatStyle(
      date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
    guard !calendar.isDate(until, inSameDayAs: now) else {
      return "Back around \(until.formatted(time))"
    }
    let weekday = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
      .weekday(.wide)
    return "Back around \(until.formatted(weekday)) \(until.formatted(time))"
  }
}
