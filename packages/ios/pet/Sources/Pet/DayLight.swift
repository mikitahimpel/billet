import Foundation

/// The light of one hour of the day, as plain numbers a room can be lit by. Worked out from the
/// clock alone: no location is involved, so sunrise and sunset are the same everywhere.
public struct DayLight: Hashable, Sendable {
  public enum Phase: String, CaseIterable, Hashable, Sendable {
    case morning
    case day
    case goldenHour
    case night
  }

  public var phase: Phase
  /// From 0 at night to 1 at noon: how much daylight comes in.
  public var sun: Double
  /// From 0 for white light to 1 for the orange of a low sun.
  public var warmth: Double
  /// Whether a room lamp would be on.
  public var lampOn: Bool

  public init(phase: Phase, sun: Double, warmth: Double, lampOn: Bool) {
    self.phase = phase
    self.sun = sun
    self.warmth = warmth
    self.lampOn = lampOn
  }

  /// The light at `hour`, from 0 up to but not including 24, minutes as a fraction.
  public static func at(hour: Double) -> DayLight {
    let hour = hour.truncatingRemainder(dividingBy: 24) + (hour < 0 ? 24 : 0)
    let phase: Phase =
      switch hour {
      case 5..<10: .morning
      case 10..<17: .day
      case 17..<21: .goldenHour
      default: .night
      }
    // Daylight rises from 5:30, peaks at 13:00 and is gone by 20:30.
    let sun = hour > 5.5 && hour < 20.5 ? sin((hour - 5.5) / 15 * .pi) : 0
    let low = 1 - min(abs(hour - 13) / 7.5, 1)
    let warmth = phase == .night ? 0.2 : 1 - low * low * 0.9
    return DayLight(
      phase: phase, sun: max(sun, 0), warmth: min(max(warmth, 0), 1),
      lampOn: phase == .night || phase == .goldenHour)
  }

  /// `date` moved by whole hours so that in `zone` it reads `hour`, minutes kept, or `date` as
  /// it is when `hour` is `nil`. Moving the date rather than the hour keeps every other time zone
  /// in step, so the partner's sky moves with it.
  public static func pretending(_ date: Date, hour: Int?, in zone: TimeZone) -> Date {
    guard let hour else { return date }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let now = calendar.component(.hour, from: date)
    return date.addingTimeInterval(Double(hour - now) * 3600)
  }

  public static func at(_ date: Date, in zone: TimeZone) -> DayLight {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return at(hour: Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60)
  }
}
