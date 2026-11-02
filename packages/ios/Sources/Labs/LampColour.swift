import DesignSystem
import Foundation

/// How today feels, as the colour of the lamp in the window. Five colours from the palette, and no
/// words on them: each partner decides what a colour means.
public enum LampColour: String, CaseIterable, Codable, Sendable {
  case gold
  case rose
  case green
  case amber
  case cream

  public static let standard = LampColour.gold

  public var swatch: Swatch {
    switch self {
    case .gold: Palette.light
    case .rose: Palette.clayLit
    case .green: Palette.greenBright
    case .amber: Palette.woodLit
    case .cream: Palette.paperTurned
    }
  }

  /// For VoiceOver only. The screen shows colour alone.
  public var spokenName: String {
    switch self {
    case .gold: "Gold"
    case .rose: "Rose"
    case .green: "Green"
    case .amber: "Amber"
    case .cream: "Cream"
    }
  }
}

/// What this phone knows about the partner's window.
public struct PartnerGlow: Hashable, Sendable {
  public var colour: LampColour
  /// False once the partner has said goodnight.
  public var lampOn: Bool
  /// The partner's time zone, such as `Asia/Tokyo`. Nothing finer than that is shared.
  public var timeZoneID: String?

  public init(colour: LampColour = .standard, lampOn: Bool = true, timeZoneID: String? = nil) {
    self.colour = colour
    self.lampOn = lampOn
    self.timeZoneID = timeZoneID
  }
}
