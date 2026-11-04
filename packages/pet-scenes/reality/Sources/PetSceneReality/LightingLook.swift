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
    key: Key(colour: [1, 0.64, 0.32], warmth: 0.75, boost: 2, softness: 1.6, flicker: 0),
    fill: Fill(top: [1, 0.76, 0.5], bottom: [1, 0.6, 0.32], shift: 0.9),
    core: 160_000, rim: ([1, 0.72, 0.4], 30_000), fairy: (true, [1, 0.83, 0.55], 2.2),
    sun: (.zero, 0),
    led: [1, 0.8, 0.5], outside: [1, 0.7, 0.4], shadows: 0.5,
    haze: Haze(centre: [0.82, 0.47, 0.2], edge: [0.13, 0.06, 0.03], cover: 1), halos: 1.3,
    grade: Grade(
      tint: [1, 0.78, 0.55], tintAmount: 0.4, lift: [0.26, 0.13, 0.05], liftAmount: 0.45),
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

// MARK: - The light switch

extension LightingLook {
  /// What the room shows with its switch at `light`, over the lighting preset `preset`: the preset
  /// itself when on, the lamp low and the fairy lights when cosy, and only the moon when off.
  static func switched(_ preset: LightingLook, to light: RoomLight) -> LightingLook {
    switch light {
    case .on: preset
    case .cosy: .cosy
    case .off: .moonlight
    }
  }

  /// The look with its fairy lights glowing `fairy`'s colour, where it has a colour of its own.
  func tinted(_ fairy: FairyColour) -> LightingLook {
    guard let colour = fairy.rgb else { return self }
    var look = self
    look.fairy.colour = colour
    return look
  }

  /// The lamp turned low and the fairy lights, the strip dark: warm pools in a dim room.
  static let cosy = LightingLook(
    key: Key(colour: [1, 0.6, 0.3], warmth: 0.85, boost: 0.45, softness: 0.9, flicker: 0),
    fill: Fill(top: [0.62, 0.48, 0.4], bottom: [0.36, 0.24, 0.2], shift: -0.9),
    core: 6_000, rim: ([1, 0.72, 0.45], 12_000), fairy: (true, [1, 0.82, 0.52], 2.8),
    sun: (.zero, 0),
    led: [0.14, 0.09, 0.06], outside: [0.6, 0.6, 0.75], shadows: 0.55,
    haze: Haze(centre: [0.36, 0.18, 0.09], edge: [0.04, 0.02, 0.02], cover: 0.7), halos: 1.5,
    grade: Grade(
      tint: [1, 0.84, 0.66], tintAmount: 0.3, lift: [0.07, 0.035, 0.02], liftAmount: 0.35),
    vignette: ([0.02, 0.01, 0.01], 0.65))

  /// Every light in the room out: cool moonlight through the window, a blue rim on the cat so it
  /// still reads, and a dark cool grade.
  static let moonlight = LightingLook(
    key: Key(colour: [0.6, 0.7, 1], warmth: 0, boost: 0, softness: 0, flicker: 0),
    fill: Fill(top: [0.36, 0.46, 0.72], bottom: [0.14, 0.17, 0.3], shift: -1.7),
    core: 0, rim: ([0.58, 0.68, 1], 9_000), fairy: (false, .zero, 0), sun: (.zero, 0),
    led: [0.04, 0.05, 0.08], outside: [0.55, 0.66, 1], shadows: 0.3,
    haze: Haze(centre: [0.08, 0.1, 0.2], edge: [0.01, 0.015, 0.04], cover: 0.8), halos: 0.25,
    grade: Grade(
      tint: [0.7, 0.8, 1], tintAmount: 0.45, lift: [0.02, 0.03, 0.07], liftAmount: 0.35),
    vignette: ([0, 0, 0.02], 0.72))

  /// A bulb on a string with no current through it.
  static let unlitBulb: RGB = [0.16, 0.13, 0.11]

  /// The look `amount` of the way from `from` to `to`. Colours that go into materials move in
  /// tenths, so a fade makes a handful of materials rather than one a frame; lights and the flat
  /// layers move smoothly. `ownLED` and `ownOutside` stand in for a look that keeps the room's
  /// own colour.
  static func mix(
    _ from: LightingLook, _ to: LightingLook, by amount: Float, ownLED: RGB, ownOutside: RGB
  ) -> LightingLook {
    let t = Swift.min(Swift.max(amount, 0), 1)
    if t >= 1 { return to }
    if t <= 0 { return from }
    let step = (t * 10).rounded() / 10
    func mix(_ a: RGB, _ b: RGB) -> RGB { RGB.mix(a, b, by: t) }
    func mix(_ a: Float, _ b: Float) -> Float { a + (b - a) * t }
    let fromBulb = from.fairy.shown ? from.fairy.colour : unlitBulb
    let toBulb = to.fairy.shown ? to.fairy.colour : unlitBulb
    return LightingLook(
      key: Key(
        colour: mix(from.key.colour, to.key.colour), warmth: mix(from.key.warmth, to.key.warmth),
        boost: mix(from.key.boost, to.key.boost),
        softness: mix(from.key.softness, to.key.softness),
        flicker: mix(from.key.flicker, to.key.flicker)),
      fill: Fill(
        top: mix(from.fill.top, to.fill.top), bottom: mix(from.fill.bottom, to.fill.bottom),
        shift: mix(from.fill.shift, to.fill.shift)),
      core: mix(from.core, to.core),
      rim: (mix(from.rim.colour, to.rim.colour), mix(from.rim.intensity, to.rim.intensity)),
      fairy: (
        from.fairy.shown || to.fairy.shown, RGB.mix(fromBulb, toBulb, by: step),
        mix(from.fairy.shown ? from.fairy.spill : 0, to.fairy.shown ? to.fairy.spill : 0)
      ),
      sun: (mix(from.sun.colour, to.sun.colour), mix(from.sun.intensity, to.sun.intensity)),
      led: RGB.mix(from.led ?? ownLED, to.led ?? ownLED, by: step),
      outside: mix(from.outside ?? ownOutside, to.outside ?? ownOutside),
      shadows: mix(from.shadows, to.shadows),
      haze: Haze(
        centre: mix(from.haze.centre, to.haze.centre), edge: mix(from.haze.edge, to.haze.edge),
        cover: mix(from.haze.cover, to.haze.cover)),
      halos: mix(from.halos, to.halos),
      grade: Grade(
        tint: mix(from.grade.tint, to.grade.tint),
        tintAmount: mix(from.grade.tintAmount, to.grade.tintAmount),
        lift: mix(from.grade.lift, to.grade.lift),
        liftAmount: mix(from.grade.liftAmount, to.grade.liftAmount)),
      vignette: (
        mix(from.vignette.colour, to.vignette.colour),
        mix(from.vignette.amount, to.vignette.amount)
      ))
  }
}

extension GenzColour {
  var rgb: LightingLook.RGB { [red, green, blue] }
}
