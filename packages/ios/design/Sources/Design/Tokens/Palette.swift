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

enum Palette {
  static let screen = Adaptive(light: RGBA(hex: 0xFBF3E8), dark: RGBA(hex: 0x2A1A12))
  static let surface = Adaptive(light: RGBA(hex: 0xFFFFFF), dark: RGBA(hex: 0x3B2C25))
  static let surfaceRaised = Adaptive(light: RGBA(hex: 0xF3E6D6), dark: RGBA(hex: 0x46352C))
  /// A card is lit from above: `surfaceTop` to `surfaceBottom`, with `cardRimTop` on its upper edge.
  static let surfaceTop = Adaptive(light: RGBA(hex: 0xFFFFFF), dark: RGBA(hex: 0x4E3B30))
  static let surfaceBottom = Adaptive(light: RGBA(hex: 0xFFF7EC), dark: RGBA(hex: 0x3D2D24))
  static let warmTop = Adaptive(light: RGBA(hex: 0xFFEEDA), dark: RGBA(hex: 0x644431))
  static let warmBottom = Adaptive(light: RGBA(hex: 0xFFE2C2), dark: RGBA(hex: 0x4A3326))
  static let warmGlow = Adaptive(light: RGBA(hex: 0xFFD9A6), dark: RGBA(hex: 0x765034))
  static let cardRimTop = Adaptive(
    light: RGBA(hex: 0xFFFFFF), dark: RGBA(hex: 0xFFECD2, opacity: 0.24))
  static let cardRimBottom = Adaptive(
    light: RGBA(hex: 0x3A2114, opacity: 0.07), dark: RGBA(hex: 0xFFECD2, opacity: 0.04))
  /// Warm brown on cream, never black; nearly black on the dark screen, where only a deep one shows.
  static let cardShadow = Adaptive(
    light: RGBA(hex: 0x5A2E12, opacity: 0.16), dark: RGBA(hex: 0x0A0400, opacity: 0.5))
  static let separator = Adaptive(
    light: RGBA(hex: 0x3A2114, opacity: 0.12), dark: RGBA(hex: 0xFFFFFF, opacity: 0.14))
  static let text = Adaptive(
    light: RGBA(hex: 0x3A2114), dark: RGBA(hex: 0xFFFFFF, opacity: 0.96))
  static let textSecondary = Adaptive(
    light: RGBA(hex: 0x6B4A36), dark: RGBA(hex: 0xF3E3D0, opacity: 0.86))
  static let textTertiary = Adaptive(
    light: RGBA(hex: 0x3A2114, opacity: 0.45), dark: RGBA(hex: 0xFFFFFF, opacity: 0.5))
  static let accentText = Adaptive(light: RGBA(hex: 0x974A18), dark: honey)
  static let destructive = Adaptive(light: RGBA(hex: 0xB3261E), dark: RGBA(hex: 0xFF8A80))

  static let honey = RGBA(hex: 0xF2A65E)
  static let heroInk = RGBA(hex: 0x3A2114)

  /// Nearly opaque, so the glyph on it reads over anything behind.
  static let glassFill = Adaptive(
    light: RGBA(hex: 0xFFF8EE, opacity: 0.86), dark: RGBA(hex: 0x2A1A12, opacity: 0.78))
  static let glassGlyph = Adaptive(light: RGBA(hex: 0x3A2114), dark: RGBA(hex: 0xFFFFFF))
  static let glassGlyphSecondary = Adaptive(
    light: RGBA(hex: 0x6B4A36), dark: RGBA(hex: 0xFFFFFF, opacity: 0.88))
  static let glassRim = Adaptive(
    light: RGBA(hex: 0xFFFFFF, opacity: 0.7), dark: RGBA(hex: 0xFFFFFF, opacity: 0.18))
  static let glassSelection = Adaptive(
    light: RGBA(hex: 0xF2A65E, opacity: 0.38), dark: RGBA(hex: 0xF2A65E, opacity: 0.34))

  static let disabledFill = Adaptive(
    light: RGBA(hex: 0x3A2114, opacity: 0.08), dark: RGBA(hex: 0xFFFFFF, opacity: 0.1))
  static let disabledText = Adaptive(
    light: RGBA(hex: 0x6B4A36), dark: RGBA(hex: 0xFFFFFF, opacity: 0.66))

  static let coinFace = RGBA(hex: 0xFFD25A)
  /// The ring that keeps the coin apart from honey; `heroInk` is 7:1 on honey.
  static let coinRing = heroInk

  /// Backdrops for the contrast tests.
  static let roomBackdrop = RGBA(hex: 0x1B1410)
  static let roomBackdropBright = RGBA(hex: 0xC9A27C)
  static let cityBackdrop = RGBA(hex: 0xBFD9E8)
}
