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
  /// Honey that reads on dark, for marks drawn over a dark map or picture.
  public static let honeyBright = Color(hex: 0xFFE07A)
  public static let blushPink = Color(hex: 0xFF8FA3)

  /// A colour a drawing carries as `#RRGGBB`: the sender's ink, which may be one this build
  /// doesn't sell. Nil when the rest after the first character isn't hex.
  public init?(drawnInk hex: String) {
    guard let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
    self.init(hex: value)
  }
}

/// A rarity's colours: `tint` for rings and glows, `light` and `edge` for the soft backdrop behind art. The backdrop
/// is the light pair in either appearance, so art never sits on dark.
public struct RarityTone: Sendable {
  public let tint: Color
  public let light: Color
  public let edge: Color
}

extension Ink {
  public static let rarityCommon = RarityTone(
    tint: Color(hex: 0xE3BD8F), light: Color(hex: 0xFFF1DE), edge: Color(hex: 0xF3DDC2))
  public static let rarityRare = RarityTone(
    tint: Color(hex: 0x3CC8E0), light: Color(hex: 0xDDF6FA), edge: Color(hex: 0xB9E6EE))
  public static let rarityEpic = RarityTone(
    tint: Color(hex: 0xA466E8), light: Color(hex: 0xF1E3FF), edge: Color(hex: 0xDCC4F8))
  public static let rarityLegendary = RarityTone(
    tint: Color(hex: 0xFFB52E), light: Color(hex: 0xFFF0C4), edge: Color(hex: 0xFFDB8A))
}

extension ShapeStyle where Self == LinearGradient {
  public static var honeyGradient: LinearGradient {
    LinearGradient(
      colors: [Color(hex: 0xFFC27D), .honeyDeep], startPoint: .topLeading, endPoint: .bottomTrailing
    )
  }
}

/// `screen` to `disabledText` follow the system appearance; `primary` to `hairline` are white on
/// warm glass over the room in either appearance.
public enum Ink {
  public static let screen = Palette.screen.color
  public static let surface = Palette.surface.color
  /// Selected rows, pressed cards, chips on a surface.
  public static let surfaceRaised = Palette.surfaceRaised.color
  public static let separator = Palette.separator.color
  public static let text = Palette.text.color
  public static let textSecondary = Palette.textSecondary.color
  /// Placeholders, never body text or a disabled label that must be read.
  public static let textTertiary = Palette.textTertiary.color
  /// Honey for text; darker on cream to keep 5:1.
  public static let accentText = Palette.accentText.color
  public static let destructive = Palette.destructive.color

  public static let glassFill = Palette.glassFill.color
  public static let glassGlyph = Palette.glassGlyph.color
  public static let glassGlyphSecondary = Palette.glassGlyphSecondary.color
  public static let glassRim = Palette.glassRim.color
  public static let glassSelection = Palette.glassSelection.color

  public static let disabledFill = Palette.disabledFill.color
  public static let disabledText = Palette.disabledText.color

  public static let primary = Color.white.opacity(0.96)
  public static let secondary = Color.white.opacity(0.72)
  public static let hairline = Color.white.opacity(0.14)
  /// The text colour on honey.
  public static let heroInk = Palette.heroInk.color
  /// Print and stamp paper: the same warm white in either appearance, as a polaroid is.
  public static let paper = Color(hex: 0xFFFBF2)
  public static let paperEdge = Color(hex: 0xEADFCB)
  /// Light enough that the room still shows through, warm enough that the glass never turns grey.
  public static let glassTint = Color(hex: 0xF2A65E, opacity: 0.16)
}
