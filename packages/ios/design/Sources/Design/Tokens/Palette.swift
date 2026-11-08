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

  /// This colour laid over an opaque one.
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

  /// WCAG contrast ratio of this colour over `background`, translucent colours composited first.
  func contrast(over background: RGBA) -> Double {
    let top = over(background).luminance
    let bottom = background.luminance
    return (max(top, bottom) + 0.05) / (min(top, bottom) + 0.05)
  }
}

/// A colour with a light and a dark value.
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

/// Every value of the app's colours as numbers. `Ink` and the contrast tests read this one table.
enum Palette {
  static let screen = Adaptive(light: RGBA(hex: 0xFBF3E8), dark: RGBA(hex: 0x2A1A12))
  static let surface = Adaptive(light: RGBA(hex: 0xFFFFFF), dark: RGBA(hex: 0x3B2C25))
  static let surfaceRaised = Adaptive(light: RGBA(hex: 0xF3E6D6), dark: RGBA(hex: 0x46352C))
  static let separator = Adaptive(
    light: RGBA(hex: 0x3A2114, opacity: 0.12), dark: RGBA(hex: 0xFFFFFF, opacity: 0.14))
  static let text = Adaptive(
    light: RGBA(hex: 0x3A2114), dark: RGBA(hex: 0xFFFFFF, opacity: 0.96))
  static let textSecondary = Adaptive(
    light: RGBA(hex: 0x7A5A45), dark: RGBA(hex: 0xFFFFFF, opacity: 0.72))
  static let textTertiary = Adaptive(
    light: RGBA(hex: 0x3A2114, opacity: 0.45), dark: RGBA(hex: 0xFFFFFF, opacity: 0.5))
  static let accentText = Adaptive(light: RGBA(hex: 0x974A18), dark: honey)
  static let destructive = Adaptive(light: RGBA(hex: 0xB3261E), dark: RGBA(hex: 0xFF8A80))

  static let honey = RGBA(hex: 0xF2A65E)
  static let heroInk = RGBA(hex: 0x3A2114)

  /// The fill of a control that floats over the room or the city: nearly opaque, so the glyph on it reads over
  /// anything behind.
  static let glassFill = Adaptive(
    light: RGBA(hex: 0xFFF8EE, opacity: 0.86), dark: RGBA(hex: 0x2A1A12, opacity: 0.78))
  static let glassGlyph = Adaptive(light: RGBA(hex: 0x3A2114), dark: RGBA(hex: 0xFFFFFF))
  static let glassGlyphSecondary = Adaptive(
    light: RGBA(hex: 0x6B4A36), dark: RGBA(hex: 0xFFFFFF, opacity: 0.88))
  /// The edge of every glass surface: a lit line over the dark room, a soft one over cream.
  static let glassRim = Adaptive(
    light: RGBA(hex: 0xFFFFFF, opacity: 0.7), dark: RGBA(hex: 0xFFFFFF, opacity: 0.18))
  /// The selected item inside a glass bar: the tab, the room. Its label is `glassGlyph`.
  static let glassSelection = Adaptive(
    light: RGBA(hex: 0xF2A65E, opacity: 0.38), dark: RGBA(hex: 0xF2A65E, opacity: 0.34))

  /// A disabled button: flat and quiet, its label still readable.
  static let disabledFill = Adaptive(
    light: RGBA(hex: 0x3A2114, opacity: 0.08), dark: RGBA(hex: 0xFFFFFF, opacity: 0.1))
  static let disabledText = Adaptive(
    light: RGBA(hex: 0x6B4A36), dark: RGBA(hex: 0xFFFFFF, opacity: 0.66))

  static let coinFace = RGBA(hex: 0xFFD25A)
  /// The ring that keeps the coin apart from honey; `heroInk` is 7:1 on honey.
  static let coinRing = heroInk

  /// Backdrops a floating control sits on, for the contrast tests: the dark room and the cream city.
  static let roomBackdrop = RGBA(hex: 0x1B1410)
  static let roomBackdropBright = RGBA(hex: 0xC9A27C)
  static let cityBackdrop = RGBA(hex: 0xBFD9E8)
}
