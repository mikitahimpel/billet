import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

extension Color {
  public init(hex: UInt32, opacity: Double = 1) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }

  /// A colour that follows the system appearance.
  public init(light: Color, dark: Color) {
    #if canImport(UIKit)
      self.init(
        uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    #else
      self = light
    #endif
  }

  public static let honey = Color(hex: 0xF2A65E)
  public static let honeyDeep = Color(hex: 0xD9784A)
  public static let blushPink = Color(hex: 0xFF8FA3)
}

extension ShapeStyle where Self == LinearGradient {
  public static var honeyGradient: LinearGradient {
    LinearGradient(
      colors: [Color(hex: 0xFFC27D), .honeyDeep], startPoint: .topLeading, endPoint: .bottomTrailing
    )
  }
}

/// The app's colours. The adaptive set (`screen` to `accentText`) follows the system appearance and is what
/// screens use; the "on room" set is white on warm glass over the scene in either appearance.
public enum Ink {
  /// Full screens and sheets: warm cream in light, deep warm brown in dark.
  public static let screen = Color(light: Color(hex: 0xFBF3E8), dark: Color(hex: 0x2A1A12))
  /// Cards and list rows on `screen`.
  public static let surface = Color(light: .white, dark: Color(hex: 0x3B2C25))
  /// Selected rows, pressed cards, chips on a surface.
  public static let surfaceRaised = Color(light: Color(hex: 0xF3E6D6), dark: Color(hex: 0x46352C))
  public static let separator = Color(
    light: Color(hex: 0x3A2114, opacity: 0.12), dark: .white.opacity(0.14))
  /// Titles and body text; 13.6:1 on the cream screen.
  public static let text = Color(light: Color(hex: 0x3A2114), dark: .white.opacity(0.96))
  /// Subtitles and captions; 5.7:1 on the cream screen.
  public static let textSecondary = Color(light: Color(hex: 0x7A5A45), dark: .white.opacity(0.72))
  /// Placeholders, never body text or a disabled label that must be read.
  public static let textTertiary = Color(
    light: Color(hex: 0x3A2114, opacity: 0.45), dark: .white.opacity(0.5))
  /// Honey for text: links, text buttons, checkmarks. Darker on cream to keep 5:1; honey itself in dark.
  public static let accentText = Color(light: Color(hex: 0xA4521C), dark: .honey)

  /// White on warm glass over the room.
  public static let primary = Color.white.opacity(0.96)
  public static let secondary = Color.white.opacity(0.72)
  public static let hairline = Color.white.opacity(0.14)
  /// Deep warm brown, the text colour on honey (7.4:1).
  public static let heroInk = Color(hex: 0x3A2114)
  /// A breath of honey laid into Liquid Glass: light enough that the room still shows through, warm enough
  /// that it never turns grey.
  public static let glassTint = Color(hex: 0xF2A65E, opacity: 0.16)
}
