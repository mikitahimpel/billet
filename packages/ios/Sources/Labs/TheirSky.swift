import DesignSystem
import Foundation

/// The time of day where the partner is, from their time zone alone. No location is involved.
public enum TheirSky: String, CaseIterable, Sendable {
  case dawn
  case day
  case dusk
  case night

  /// The sky at a local `hour`, 0 to 23: dawn 5 to 7, day 8 to 17, dusk 18 to 20, night after.
  public static func at(hour: Int) -> TheirSky {
    switch hour {
    case 5...7: .dawn
    case 8...17: .day
    case 18...20: .dusk
    default: .night
    }
  }

  /// The sky over `timeZoneID` at `date`, or nil when that is not a time zone.
  public static func over(timeZoneID: String, at date: Date) -> TheirSky? {
    guard let zone = TimeZone(identifier: timeZoneID) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return at(hour: calendar.component(.hour, from: date))
  }

  public var title: String {
    switch self {
    case .dawn: "Dawn"
    case .day: "Daytime"
    case .dusk: "Dusk"
    case .night: "Night"
    }
  }

  /// Top and bottom of the sky, from the palette.
  public var colours: (top: Swatch, bottom: Swatch) {
    switch self {
    case .dawn: (Palette.skyLit, Palette.woodLit)
    case .day: (Palette.greenBright, Palette.lightWarm)
    case .dusk: (Palette.clayNight, Palette.clayLit)
    case .night: (Palette.skyNight, Palette.sky)
    }
  }
}
