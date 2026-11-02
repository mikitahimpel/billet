import Foundation
import Observation
import Pet

/// Going away: the porch light stays on for a few days and the streak waits. It is free and always
/// available, and cannot be bought or topped up.
public struct PorchLight: Codable, Equatable, Sendable {
  public static let longest = 3

  /// The first night, as the start of that day.
  public let from: Date
  public let nights: Int

  public init(from: Date, nights: Int, calendar: Calendar = .current) {
    self.from = calendar.startOfDay(for: from)
    self.nights = min(Self.longest, max(1, nights))
  }

  /// The days the light covers, as `yyyy-MM-dd`, counting from `from`.
  public func covered(calendar: Calendar) -> Set<String> {
    Set(
      (0..<nights).compactMap { calendar.date(byAdding: .day, value: $0, to: from) }
        .map { TreatDay.key(for: $0, calendar: calendar) })
  }

  /// The morning after the last night: when the streak starts waiting for nobody again.
  public func ends(calendar: Calendar) -> Date {
    calendar.date(byAdding: .day, value: nights, to: from) ?? from
  }

  public func isOn(at now: Date, calendar: Calendar) -> Bool {
    now < ends(calendar: calendar)
  }
}

/// The porch light, kept in `defaults`.
@MainActor
@Observable
public final class PorchLightStore {
  public private(set) var light: PorchLight?

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let key: String

  public init(defaults: UserDefaults = .standard, key: String = "labs.porchLight") {
    self.defaults = defaults
    self.key = key
    light = defaults.data(forKey: key).flatMap {
      try? JSONDecoder().decode(PorchLight.self, from: $0)
    }
  }

  /// The days to keep out of the streak's way: empty once the light has gone out.
  public func covered(now: Date, calendar: Calendar) -> Set<String> {
    guard let light else { return [] }
    return light.covered(calendar: calendar)
  }

  public func leaveOn(nights: Int, now: Date, calendar: Calendar) {
    light = PorchLight(from: now, nights: nights, calendar: calendar)
    defaults.set(try? JSONEncoder().encode(light), forKey: key)
  }

  public func switchOff() {
    light = nil
    defaults.removeObject(forKey: key)
  }
}
