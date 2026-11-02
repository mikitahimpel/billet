import Pet
import SwiftUI

/// Everything one lighting preset sets, the same for every room: the lamp as key light, the
/// ambient fill, a rim light on the cat, fairy lights and their spill, a low sun, the LED's colour,
/// soft shadows, and the flat layers over the view: haze, halos on the lights, grading and
/// vignette. A new preset is one more value of this.
struct LightingLook: Equatable, Sendable {
  /// A colour as red, green and blue from 0 to 1.
  typealias RGB = SIMD3<Float>

  struct Key: Equatable, Sendable {
    /// What the lamp's colour moves towards, and how far.
    var colour: RGB
    var warmth: Float
    /// How much brighter than its own the lamp shines.
    var boost: Float
    /// How much wider and softer its light falls.
    var softness: Float
    /// How much the lamp flickers, 0 for steady.
    var flicker: Float
  }

  struct Fill: Equatable, Sendable {
    /// The ambient light from above and from below.
    var top: RGB
    var bottom: RGB
    /// Added to the ambient light's exponent: negative is darker.
    var shift: Float
  }

  struct Haze: Equatable, Sendable {
    /// The glow right around the room, and the colour the view falls off to at its edges.
    var centre: RGB
    var edge: RGB
    /// How much of the view the haze covers, from 0 (none) to 1 (it replaces the night behind).
    var cover: Float
  }

  struct Grade: Equatable, Sendable {
    /// Multiplied over the whole view, to tint it.
    var tint: RGB
    var tintAmount: Float
    /// Added under the darks, so nothing is black and contrast drops.
    var lift: RGB
    var liftAmount: Float
  }

  var key: Key
  var fill: Fill
  /// A soft light low in the middle of the room, so it glows from inside like a lantern.
  var core: Float
  /// The rim light behind the cat.
  var rim: (colour: RGB, intensity: Float)
  /// The fairy lights: whether they hang, their colour, and how much light they spill.
  var fairy: (shown: Bool, colour: RGB, spill: Float)
  /// A low sun through the window, 0 for none.
  var sun: (colour: RGB, intensity: Float)
  /// The LED strip's colour, or `nil` for the room's own.
  var led: RGB?
  /// The light from outside the window, or `nil` for the room's own.
  var outside: RGB?
  /// How dark the soft shadows under things are, 0 for none.
  var shadows: Float
  var haze: Haze
  /// How strongly the lights' halos show, 0 for none.
  var halos: Float
  var grade: Grade
  /// How dark the edges of the view get, and the colour they go to.
  var vignette: (colour: RGB, amount: Float)

  static func == (left: LightingLook, right: LightingLook) -> Bool {
    left.key == right.key && left.fill == right.fill && left.core == right.core
      && left.rim == right.rim
      && left.fairy == right.fairy && left.sun == right.sun && left.led == right.led
      && left.outside == right.outside && left.shadows == right.shadows && left.haze == right.haze
      && left.halos == right.halos && left.grade == right.grade && left.vignette == right.vignette
  }

  /// Whether anything is added to the room at all.
  var isLit: Bool { self != .off }

  static func of(_ lighting: RoomLighting) -> LightingLook {
    switch lighting {
    case .off: .off
    case .amberLantern: .amberLantern
    case .fairyLights: .fairyLights
    case .goldenHour: .goldenHour
    case .neonNight: .neonNight
    case .candle: .candle
    }
  }

  static let off = LightingLook(
    key: Key(colour: [1, 0.76, 0.42], warmth: 0, boost: 1, softness: 0, flicker: 0),
    fill: Fill(top: .zero, bottom: .zero, shift: 0), core: 0, rim: (.zero, 0),
    fairy: (false, .zero, 0),
    sun: (.zero, 0), led: nil, outside: nil, shadows: 0,
    haze: Haze(centre: .zero, edge: .zero, cover: 0), halos: 0,
    grade: Grade(tint: .one, tintAmount: 0, lift: .zero, liftAmount: 0), vignette: (.zero, 0))

  /// The room glowing from inside like a lantern, in a dark warm haze brightest around it.
  static let amberLantern = LightingLook(
    key: Key(colour: [1, 0.62, 0.3], warmth: 0.7, boost: 1.4, softness: 1.2, flicker: 0),
    fill: Fill(top: [1, 0.78, 0.55], bottom: [0.75, 0.45, 0.25], shift: 0.35),
    core: 70_000, rim: ([1, 0.72, 0.4], 30_000), fairy: (true, [1, 0.83, 0.55], 1.2),
    sun: (.zero, 0),
    led: [1, 0.8, 0.5], outside: [1, 0.7, 0.4], shadows: 0.55,
    haze: Haze(centre: [0.78, 0.44, 0.2], edge: [0.13, 0.06, 0.03], cover: 1), halos: 1.2,
    grade: Grade(
      tint: [1, 0.8, 0.6], tintAmount: 0.45, lift: [0.24, 0.12, 0.05], liftAmount: 0.5),
    vignette: ([0.1, 0.04, 0.01], 0.55))

  /// A darker room lit mostly by strings of warm fairy lights.
  static let fairyLights = LightingLook(
    key: Key(colour: [1, 0.66, 0.36], warmth: 0.5, boost: 0.55, softness: 0.6, flicker: 0),
    fill: Fill(top: [0.7, 0.6, 0.55], bottom: [0.4, 0.3, 0.3], shift: -0.6),
    core: 15_000, rim: ([1, 0.78, 0.5], 16_000), fairy: (true, [1, 0.86, 0.6], 2.4),
    sun: (.zero, 0),
    led: [1, 0.82, 0.55], outside: nil, shadows: 0.5,
    haze: Haze(centre: [0.42, 0.22, 0.12], edge: [0.05, 0.03, 0.03], cover: 0.6), halos: 1.6,
    grade: Grade(
      tint: [1, 0.88, 0.74], tintAmount: 0.25, lift: [0.08, 0.04, 0.03], liftAmount: 0.4),
    vignette: ([0.03, 0.02, 0.02], 0.6))

  /// A low warm sun through the window, long soft shadows, a golden cast.
  static let goldenHour = LightingLook(
    key: Key(colour: [1, 0.74, 0.45], warmth: 0.3, boost: 0.7, softness: 0.8, flicker: 0),
    fill: Fill(top: [1, 0.86, 0.66], bottom: [0.8, 0.6, 0.45], shift: 0.5),
    core: 20_000, rim: ([1, 0.75, 0.42], 22_000), fairy: (false, .zero, 0),
    sun: ([1, 0.72, 0.4], 2_600),
    led: nil, outside: [1, 0.75, 0.42], shadows: 0.45,
    haze: Haze(centre: [0.95, 0.66, 0.36], edge: [0.38, 0.2, 0.1], cover: 0.75), halos: 0.6,
    grade: Grade(
      tint: [1, 0.86, 0.62], tintAmount: 0.35, lift: [0.2, 0.12, 0.05], liftAmount: 0.3),
    vignette: ([0.2, 0.1, 0.03], 0.35))

  /// Gen Z LED: a pink and purple strip, cool light from the window.
  static let neonNight = LightingLook(
    key: Key(colour: [1, 0.5, 0.75], warmth: 0.35, boost: 0.6, softness: 0.4, flicker: 0),
    fill: Fill(top: [0.6, 0.55, 0.95], bottom: [0.4, 0.25, 0.5], shift: -0.2),
    core: 15_000, rim: ([1, 0.35, 0.8], 34_000), fairy: (false, .zero, 0), sun: (.zero, 0),
    led: [1, 0.3, 0.75], outside: [0.45, 0.65, 1], shadows: 0.45,
    haze: Haze(centre: [0.42, 0.14, 0.45], edge: [0.04, 0.03, 0.1], cover: 0.65), halos: 1.4,
    grade: Grade(
      tint: [0.92, 0.82, 1], tintAmount: 0.25, lift: [0.1, 0.03, 0.14], liftAmount: 0.4),
    vignette: ([0.03, 0.01, 0.06], 0.5))

  /// Very dim, a single flickering warm key.
  static let candle = LightingLook(
    key: Key(colour: [1, 0.55, 0.22], warmth: 0.9, boost: 0.8, softness: 0.3, flicker: 0.22),
    fill: Fill(top: [0.5, 0.35, 0.25], bottom: [0.25, 0.15, 0.1], shift: -1.1),
    core: 0, rim: ([1, 0.6, 0.3], 10_000), fairy: (false, .zero, 0), sun: (.zero, 0),
    led: [0.6, 0.35, 0.15], outside: [0.35, 0.3, 0.4], shadows: 0.6,
    haze: Haze(centre: [0.3, 0.13, 0.05], edge: [0.02, 0.01, 0.01], cover: 0.85), halos: 1,
    grade: Grade(
      tint: [1, 0.78, 0.55], tintAmount: 0.4, lift: [0.06, 0.025, 0.01], liftAmount: 0.3),
    vignette: ([0.01, 0.005, 0], 0.75))
}

extension LightingLook.RGB {
  static func mix(_ from: Self, _ to: Self, by amount: Float) -> Self {
    from + (to - from) * Swift.min(Swift.max(amount, 0), 1)
  }

  var colour: Color { Color(red: Double(x), green: Double(y), blue: Double(z)) }

  var genz: GenzColour {
    func channel(_ value: Float) -> UInt32 {
      UInt32((Swift.min(Swift.max(value, 0), 1) * 255).rounded())
    }
    return GenzColour(channel(x) << 16 | channel(y) << 8 | channel(z))
  }
}
