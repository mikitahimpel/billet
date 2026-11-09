import Foundation

/// How the rooms are lit, one look for every room, so looks can be compared in Labs. The raw
/// value is what gets stored, so it stays stable across releases.
public enum RoomLighting: String, CaseIterable, Codable, Hashable, Sendable {
  /// Each room lit as it was made, with no glow, haze or grading.
  case off
  /// The room glows from inside like a lantern in a warm amber haze.
  case amberLantern
  /// A darker room lit by strings of warm fairy lights.
  case fairyLights
  /// A low warm sun through the window, with long soft shadows.
  case goldenHour
  /// A pink and purple LED strip against cool light from outside.
  case neonNight
  /// Very dim, the lamp flickering like a candle.
  case candle

  public static let standard = RoomLighting.amberLantern

  public var title: String {
    switch self {
    case .off: "Off"
    case .amberLantern: "Amber lantern"
    case .fairyLights: "Fairy lights"
    case .goldenHour: "Golden hour"
    case .neonNight: "Neon night"
    case .candle: "Candle"
    }
  }

  public var detail: String {
    switch self {
    case .off: "Each room lit as it was made."
    case .amberLantern: "The room glows like a lantern in a warm haze."
    case .fairyLights: "A darker room, strings of warm lights."
    case .goldenHour: "Low sun through the window, long soft shadows."
    case .neonNight: "Pink and purple LED, cool light outside."
    case .candle: "Very dim, a flickering warm lamp."
    }
  }
}
