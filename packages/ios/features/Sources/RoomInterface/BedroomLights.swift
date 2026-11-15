import Foundation

/// The Bedroom's light switch. It is there only in the evening and at night, when the lamps are what lights the room;
/// by day there is no switch and the sun lights the room whatever was chosen the night before.
public enum BedroomLights {
  /// The choice kept on this phone, stored as its raw value under `storageKey`.
  public enum Choice: Int, Sendable, CaseIterable {
    /// Never switched: lit at night, as the room lights its own lamps.
    case unset = 0
    case on = 1
    case off = 2
  }

  public static let storageKey = "room.lights.bedroom"
  /// Local hours: the switch shows from `evening` until `morning`.
  public static let evening = 18
  public static let morning = 6

  public static func isEvening(_ date: Date, calendar: Calendar = .current) -> Bool {
    let hour = calendar.component(.hour, from: date)
    return hour >= evening || hour < morning
  }

  public static func showsSwitch(in scene: RoomScene, at date: Date, calendar: Calendar = .current)
    -> Bool
  {
    switch scene {
    case .city: isEvening(date, calendar: calendar)
    case .home, .board: false
    }
  }

  /// Whether the switch reads as on.
  public static func isLit(_ choice: Choice) -> Bool {
    switch choice {
    case .unset, .on: true
    case .off: false
    }
  }

  /// What a tap on the switch stores.
  public static func toggled(_ choice: Choice) -> Choice { isLit(choice) ? .off : .on }

  /// What the room's lamps are told: on or off in the evening, nil by day so they follow the hour.
  public static func lamps(_ choice: Choice, at date: Date, calendar: Calendar = .current) -> Bool?
  {
    isEvening(date, calendar: calendar) ? isLit(choice) : nil
  }

  /// The next time the switch comes or goes, after `date`.
  public static func nextChange(after date: Date, calendar: Calendar = .current) -> Date {
    let hours = [morning, evening].compactMap {
      calendar.nextDate(
        after: date, matching: DateComponents(hour: $0, minute: 0, second: 0),
        matchingPolicy: .nextTime)
    }
    return hours.min() ?? date.addingTimeInterval(3600)
  }
}
