import SwiftUI

enum Appearance: CaseIterable, Sendable {
  case light
  case dark
}

/// A colour as numbers, so contrast can be computed in tests; `Ink` turns each one into a `Color`.
struct RGBA: Equatable, Sendable {
  var red: Double
  var green: Double
  var blue: Double
  var alpha: Double

  init(hex: UInt32, opacity: Double = 1) {
    red = Double((hex >> 16) & 0xFF) / 255
    green = Double((hex >> 8) & 0xFF) / 255
    blue = Double(hex & 0xFF) / 255
    alpha = opacity
  }

  var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }

  func over(_ background: RGBA) -> RGBA {
    var result = background
    result.red = red * alpha + background.red * (1 - alpha)
    result.green = green * alpha + background.green * (1 - alpha)
    result.blue = blue * alpha + background.blue * (1 - alpha)
    result.alpha = 1
    return result
  }

  /// WCAG relative luminance.
  var luminance: Double {
    func linear(_ value: Double) -> Double {
      value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// WCAG contrast ratio, translucent colours composited first.
  func contrast(over background: RGBA) -> Double {
    let top = over(background).luminance
    let bottom = background.luminance
    return (max(top, bottom) + 0.05) / (min(top, bottom) + 0.05)
  }
}

struct Adaptive: Equatable, Sendable {
  var light: RGBA
  var dark: RGBA

  init(light: RGBA, dark: RGBA) {
    self.light = light
    self.dark = dark
  }

  init(_ both: RGBA) { self.init(light: both, dark: both) }

  func value(_ appearance: Appearance) -> RGBA { appearance == .light ? light : dark }

  var color: Color { Color(light: light.color, dark: dark.color) }
}

/// Every colour of one look. `Palette` serves the current look's; `ContrastTests` checks each look.
struct Tones: Equatable, Sendable {
  var screen: Adaptive
  var surface: Adaptive
  var surfaceRaised: Adaptive
  /// A recess in a card: darker than the card's foot in dark, with `wellShade` on its upper edge.
  var well: Adaptive
  var wellShade: Adaptive
  /// A card is lit from above: `surfaceTop` to `surfaceBottom`, with `cardRimTop` on its upper edge.
  var surfaceTop: Adaptive
  var surfaceBottom: Adaptive
  var warmTop: Adaptive
  var warmBottom: Adaptive
  var warmGlow: Adaptive
  var cardRimTop: Adaptive
  var cardRimBottom: Adaptive
  var cardShadow: Adaptive
  var separator: Adaptive
  var text: Adaptive
  var textSecondary: Adaptive
  var textTertiary: Adaptive
  var accentText: Adaptive
  var destructive: Adaptive

  var honey: RGBA
  var honeyDeep: RGBA
  /// The lit upper edge of a honey face.
  var honeyLight: RGBA
  var heroInk: RGBA

  var glassFill: Adaptive
  var glassGlyph: Adaptive
  var glassGlyphSecondary: Adaptive
  var glassRim: Adaptive
  var glassSelection: Adaptive

  var disabledFill: Adaptive
  var disabledText: Adaptive

  /// The warm dark behind the room, under the tab roots' header, and in the contrast tests.
  var roomBackdrop: RGBA
  /// The glow behind the room, from its centre out to `roomBackdrop`.
  var backdrop: [RGBA]
}

enum Palette {
  static let classic = Tones(
    screen: Adaptive(light: RGBA(hex: 0xFBF3E8), dark: RGBA(hex: 0x2A1A12)),
    surface: Adaptive(light: RGBA(hex: 0xFFFFFF), dark: RGBA(hex: 0x3B2C25)),
    surfaceRaised: Adaptive(light: RGBA(hex: 0xF3E6D6), dark: RGBA(hex: 0x46352C)),
    well: Adaptive(light: RGBA(hex: 0xF3E6D6), dark: RGBA(hex: 0x2F211A)),
    wellShade: Adaptive(
      light: RGBA(hex: 0x3A2114, opacity: 0.14), dark: RGBA(hex: 0x0A0400, opacity: 0.45)),
    surfaceTop: Adaptive(light: RGBA(hex: 0xFFFFFF), dark: RGBA(hex: 0x4E3B30)),
    surfaceBottom: Adaptive(light: RGBA(hex: 0xFFF7EC), dark: RGBA(hex: 0x3D2D24)),
    warmTop: Adaptive(light: RGBA(hex: 0xFFEEDA), dark: RGBA(hex: 0x644431)),
    warmBottom: Adaptive(light: RGBA(hex: 0xFFE2C2), dark: RGBA(hex: 0x4A3326)),
    warmGlow: Adaptive(light: RGBA(hex: 0xFFD9A6), dark: RGBA(hex: 0x765034)),
    cardRimTop: Adaptive(light: RGBA(hex: 0xFFFFFF), dark: RGBA(hex: 0xFFECD2, opacity: 0.24)),
    cardRimBottom: Adaptive(
      light: RGBA(hex: 0x3A2114, opacity: 0.07), dark: RGBA(hex: 0xFFECD2, opacity: 0.04)),
    // Warm brown on cream, never black; nearly black on the dark screen, where only a deep one shows.
    cardShadow: Adaptive(
      light: RGBA(hex: 0x8A5A2B, opacity: 0.16), dark: RGBA(hex: 0x0A0400, opacity: 0.5)),
    separator: Adaptive(
      light: RGBA(hex: 0x3A2114, opacity: 0.12), dark: RGBA(hex: 0xFFFFFF, opacity: 0.14)),
    text: Adaptive(light: RGBA(hex: 0x3A2114), dark: RGBA(hex: 0xFFFFFF, opacity: 0.96)),
    textSecondary: Adaptive(
      light: RGBA(hex: 0x6B4A36), dark: RGBA(hex: 0xF3E3D0, opacity: 0.86)),
    textTertiary: Adaptive(
      light: RGBA(hex: 0x3A2114, opacity: 0.45), dark: RGBA(hex: 0xFFFFFF, opacity: 0.5)),
    accentText: Adaptive(light: RGBA(hex: 0x974A18), dark: RGBA(hex: 0xF2A65E)),
    destructive: Adaptive(light: RGBA(hex: 0xB3261E), dark: RGBA(hex: 0xFF8A80)),
    honey: RGBA(hex: 0xF2A65E),
    honeyDeep: RGBA(hex: 0xD9784A),
    honeyLight: RGBA(hex: 0xFFC27D),
    heroInk: RGBA(hex: 0x3A2114),
    // Nearly opaque, so the glyph on it reads over anything behind.
    glassFill: Adaptive(
      light: RGBA(hex: 0xFFF8EE, opacity: 0.86), dark: RGBA(hex: 0x2A1A12, opacity: 0.78)),
    glassGlyph: Adaptive(light: RGBA(hex: 0x3A2114), dark: RGBA(hex: 0xFFFFFF)),
    glassGlyphSecondary: Adaptive(
      light: RGBA(hex: 0x6B4A36), dark: RGBA(hex: 0xFFFFFF, opacity: 0.88)),
    glassRim: Adaptive(
      light: RGBA(hex: 0xFFFFFF, opacity: 0.7), dark: RGBA(hex: 0xFFFFFF, opacity: 0.18)),
    glassSelection: Adaptive(
      light: RGBA(hex: 0xF2A65E, opacity: 0.38), dark: RGBA(hex: 0xF2A65E, opacity: 0.34)),
    disabledFill: Adaptive(
      light: RGBA(hex: 0x3A2114, opacity: 0.08), dark: RGBA(hex: 0xFFFFFF, opacity: 0.1)),
    disabledText: Adaptive(
      light: RGBA(hex: 0x6B4A36), dark: RGBA(hex: 0xFFFFFF, opacity: 0.66)),
    roomBackdrop: RGBA(hex: 0x1B1410),
    backdrop: [RGBA(hex: 0xF4BF7E), RGBA(hex: 0xB36E3A), RGBA(hex: 0x4A2C1B), RGBA(hex: 0x24150D)]
  )

  /// The landing's night in the dark appearance; the light appearance keeps the cream of `classic`
  /// and takes only the amber.
  static let dusk: Tones = {
    let ink: UInt32 = 0xF7E7D4
    var tones = classic
    tones.screen.dark = RGBA(hex: 0x110A07)
    tones.surface.dark = RGBA(hex: 0x24170F)
    tones.surfaceRaised.dark = RGBA(hex: 0x33231A)
    tones.well.dark = RGBA(hex: 0x150D08)
    tones.wellShade.dark = RGBA(hex: 0x000000, opacity: 0.5)
    tones.surfaceTop.dark = RGBA(hex: 0x2E1E15)
    tones.surfaceBottom.dark = RGBA(hex: 0x1F140D)
    tones.warmTop.dark = RGBA(hex: 0x4A2E18)
    tones.warmBottom.dark = RGBA(hex: 0x32200F)
    tones.warmGlow.dark = RGBA(hex: 0x6E421C)
    tones.cardRimTop.dark = RGBA(hex: ink, opacity: 0.16)
    tones.cardRimBottom.dark = RGBA(hex: ink, opacity: 0.04)
    tones.cardShadow.dark = RGBA(hex: 0x000000, opacity: 0.6)
    tones.separator.dark = RGBA(hex: ink, opacity: 0.13)
    tones.text.dark = RGBA(hex: ink)
    tones.textSecondary.dark = RGBA(hex: ink, opacity: 0.72)
    tones.textTertiary.dark = RGBA(hex: ink, opacity: 0.5)
    tones.accentText.dark = RGBA(hex: 0xFFB46B)
    tones.destructive.dark = RGBA(hex: 0xFF9A8C)
    tones.honey = RGBA(hex: 0xFFB46B)
    tones.honeyDeep = RGBA(hex: 0xE08A3C)
    tones.honeyLight = RGBA(hex: 0xFFCF7A)
    tones.glassFill.dark = RGBA(hex: 0x110A07, opacity: 0.8)
    tones.glassGlyph.dark = RGBA(hex: ink)
    tones.glassGlyphSecondary.dark = RGBA(hex: ink, opacity: 0.8)
    tones.glassRim.dark = RGBA(hex: ink, opacity: 0.16)
    tones.glassSelection.dark = RGBA(hex: 0xFFB46B, opacity: 0.22)
    tones.disabledFill.dark = RGBA(hex: ink, opacity: 0.1)
    tones.disabledText.dark = RGBA(hex: ink, opacity: 0.66)
    tones.roomBackdrop = RGBA(hex: 0x0A0605)
    tones.backdrop = [
      RGBA(hex: 0x6B3F1C), RGBA(hex: 0x3A2210), RGBA(hex: 0x170D08), RGBA(hex: 0x0A0605),
    ]
    return tones
  }()

  static func tones(_ look: Look) -> Tones {
    switch look {
    case .classic: classic
    case .dusk: dusk
    }
  }

  static let current = tones(Look.current)

  static var screen: Adaptive { current.screen }
  static var surface: Adaptive { current.surface }
  static var surfaceRaised: Adaptive { current.surfaceRaised }
  static var well: Adaptive { current.well }
  static var wellShade: Adaptive { current.wellShade }
  static var surfaceTop: Adaptive { current.surfaceTop }
  static var surfaceBottom: Adaptive { current.surfaceBottom }
  static var warmTop: Adaptive { current.warmTop }
  static var warmBottom: Adaptive { current.warmBottom }
  static var warmGlow: Adaptive { current.warmGlow }
  static var cardRimTop: Adaptive { current.cardRimTop }
  static var cardRimBottom: Adaptive { current.cardRimBottom }
  static var cardShadow: Adaptive { current.cardShadow }
  static var separator: Adaptive { current.separator }
  static var text: Adaptive { current.text }
  static var textSecondary: Adaptive { current.textSecondary }
  static var textTertiary: Adaptive { current.textTertiary }
  static var accentText: Adaptive { current.accentText }
  static var destructive: Adaptive { current.destructive }

  static var honey: RGBA { current.honey }
  static var honeyDeep: RGBA { current.honeyDeep }
  static var honeyLight: RGBA { current.honeyLight }
  static var heroInk: RGBA { current.heroInk }

  static var glassFill: Adaptive { current.glassFill }
  static var glassGlyph: Adaptive { current.glassGlyph }
  static var glassGlyphSecondary: Adaptive { current.glassGlyphSecondary }
  static var glassRim: Adaptive { current.glassRim }
  static var glassSelection: Adaptive { current.glassSelection }

  static var disabledFill: Adaptive { current.disabledFill }
  static var disabledText: Adaptive { current.disabledText }

  static let coinFace = RGBA(hex: 0xFFD25A)
  /// The ring that keeps the coin apart from honey; `heroInk` is 7:1 on honey.
  static var coinRing: RGBA { current.heroInk }

  static var roomBackdrop: RGBA { current.roomBackdrop }
  /// Backdrops for the contrast tests.
  static let roomBackdropBright = RGBA(hex: 0xC9A27C)
  static let cityBackdrop = RGBA(hex: 0xBFD9E8)
}
