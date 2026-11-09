import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// Plain sRGB numbers, so colours can be mixed.
struct ViewColour: Hashable, Sendable {
  var red: Double
  var green: Double
  var blue: Double

  init(_ hex: UInt32) {
    red = Double((hex >> 16) & 0xFF) / 255
    green = Double((hex >> 8) & 0xFF) / 255
    blue = Double(hex & 0xFF) / 255
  }

  init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// Saturated, `hue` from 0 to 1: for LED strips and neon.
  init(hue: Double, saturation: Double = 0.75) {
    let h = (hue - hue.rounded(.down)) * 6
    let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
    let (r, g, b): (Double, Double, Double) =
      switch Int(h) {
      case 0: (1, x, 0)
      case 1: (x, 1, 0)
      case 2: (0, 1, x)
      case 3: (0, x, 1)
      case 4: (x, 0, 1)
      default: (1, 0, x)
      }
    let floor = 1 - saturation
    red = floor + saturation * r
    green = floor + saturation * g
    blue = floor + saturation * b
  }

  func mixed(with other: ViewColour, by share: Double) -> ViewColour {
    let t = min(max(share, 0), 1)
    return ViewColour(
      red: red + (other.red - red) * t, green: green + (other.green - green) * t,
      blue: blue + (other.blue - blue) * t)
  }

  /// Lighter towards white by `share`, or darker towards black for a negative one.
  func lit(_ share: Double) -> ViewColour {
    share >= 0
      ? mixed(with: ViewColour(0xFFFFFF), by: share) : mixed(with: ViewColour(0x000000), by: -share)
  }

  func color(_ opacity: Double = 1) -> Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
  }

  var shading: GraphicsContext.Shading { .color(color()) }
}

/// From the back. The sky behind and the glass in front are drawn for every view by the view system.
enum ViewPlane: Int, CaseIterable, Hashable, Sendable {
  /// Hills, a skyline, a water tower: the furthest silhouettes.
  case far
  /// Roofs, power lines, trees behind the street.
  case middle
  /// The houses across the street, the street lamp, the road.
  case street
  /// A branch, a fence, a railing: what is just outside the glass.
  case near

  /// Share of the window's on-screen movement the plane follows: near ones almost all, far ones hardly any.
  var follow: CGFloat {
    switch self {
    case .far: 0.2
    case .middle: 0.42
    case .street: 0.62
    case .near: 0.85
    }
  }
}

/// The colours of one hour in one weather, from the style bible's palette table.
struct ViewPalette: Hashable, Sendable {
  var skyTop: ViewColour
  var skyMiddle: ViewColour
  var horizon: ViewColour
  var far: ViewColour
  var middle: ViewColour
  var street: ViewColour
  var near: ViewColour
  /// From 0 to 1, how many of the neighbours' windows are lit.
  var litShare: Double
  /// Whether street lamps, porch lights and headlights are on.
  var lampsOn: Bool
  /// How many stars show: 1 is the usual night sky, more for a sky far from any town.
  var stars: Double
  /// Fog or haze over the far planes, from 0 to 1.
  var haze: Double
  var hazeColour: ViewColour

  static let lamp = ViewColour(0xFFC36B)
  static let lampCore = ViewColour(0xFFE2B0)
  static let tv = ViewColour(0x7FB2FF)
  static let porchRed = ViewColour(0xE5503A)
  static let snow = ViewColour(0xEEF2F7)

  /// The palette of `view`: the shared one for its hour and weather, graded to the view's place.
  init(hour: ViewHour, weather: ViewWeather, view: WindowView) {
    self.init(hour: hour, weather: weather)
    // Weather greys a place's own colour down.
    let share = weather == .clear ? 1.0 : 0.4
    switch view {
    case .suburbNight, .rainySuburb, .snowyDecember, .summerCulDeSac, .dormQuad: break
    case .fireEscape:
      // City sky: sodium glow low down, few stars.
      stars *= 0.15
      if hour == .night || hour == .dusk {
        horizon = horizon.mixed(with: ViewColour(0xB0705A), by: 0.45 * share)
        skyMiddle = skyMiddle.mixed(with: ViewColour(0x4A3A52), by: 0.3 * share)
      }
    case .pinkDusk: gradePink(hour, share: share)
    case .sunsetBeach: SunsetBeach.grade(&self, hour: hour, share: share)
    case .forestCabin: ForestCabin.grade(&self, hour: hour, share: share)
    case .moonlitPeaks: MoonlitPeaks.grade(&self, hour: hour, share: share)
    case .neonStreet: NeonStreet.grade(&self, hour: hour, share: share)
    case .rooftopsDusk: RooftopsDusk.grade(&self, hour: hour, share: share)
    case .autumnPark: AutumnPark.grade(&self, hour: hour, share: share)
    case .mistyLake: MistyLake.grade(&self, hour: hour, share: share)
    case .desertStars: DesertStars.grade(&self, hour: hour, share: share)
    }
  }

  /// Mixes the sky and the planes towards a view's own colours, `share` of the way: the sky's top,
  /// middle and horizon, then the far, middle, street and near planes.
  mutating func grade(_ colours: [UInt32], share: Double) {
    guard colours.count == 7 else { return }
    let colours = colours.map(ViewColour.init)
    skyTop = skyTop.mixed(with: colours[0], by: share)
    skyMiddle = skyMiddle.mixed(with: colours[1], by: share)
    horizon = horizon.mixed(with: colours[2], by: share)
    far = far.mixed(with: colours[3], by: share)
    middle = middle.mixed(with: colours[4], by: share)
    street = street.mixed(with: colours[5], by: share)
    near = near.mixed(with: colours[6], by: share)
  }

  private mutating func gradePink(_ hour: ViewHour, share: Double) {
    let grade: [UInt32]
    switch hour {
    case .dusk: grade = [0x3B2A6E, 0xC2629E, 0xFFA27A, 0x7A4E86, 0x4E3466, 0x34244C, 0x1E1630]
    case .night: grade = [0x0E0C26, 0x2C2458, 0x7A4A7A, 0x30285A, 0x221C42, 0x181430, 0x0E0A1E]
    case .day: grade = [0x5EA4DA, 0x9CCDEA, 0xFFE6C8, 0xB0B4C8, 0x8A90A8, 0x6A7088, 0x4A4E66]
    case .morning: grade = [0x7A8CCC, 0xD8B8D8, 0xFFC8A8, 0xB8A8C0, 0x8E80A0, 0x6C6080, 0x48405C]
    }
    self.grade(grade, share: share)
    if haze == 0 {
      hazeColour = horizon
      haze = hour == .day ? 0.2 : 0
    }
  }

  init(hour: ViewHour, weather: ViewWeather) {
    switch hour {
    case .night:
      self.init(
        0x070C18, 0x162846, 0x3A5A86, 0x20365A, 0x14233D, 0x0E1A2E, 0x0A1220,
        lit: 0.55, lamps: true, stars: 1)
    case .dusk:
      self.init(
        0x2A2550, 0x6B5B9A, 0xF28A8A, 0x5A4A7A, 0x3E3360, 0x2C2448, 0x1C1830,
        lit: 0.4, lamps: true, stars: 0.25)
    case .day:
      self.init(
        0x5E9CD3, 0x8EC5E8, 0xD8ECF5, 0x9DB8CF, 0x7A95AE, 0x5C7690, 0x3F536A,
        lit: 0, lamps: false, stars: 0)
    case .morning:
      self.init(
        0x6E8FC4, 0xB8C8E6, 0xFFD9B8, 0xB9B4C8, 0x8F8CA6, 0x6E6C88, 0x4A4862,
        lit: 0.15, lamps: false, stars: 0)
    }
    apply(weather, hour: hour)
  }

  private init(
    _ top: UInt32, _ middleSky: UInt32, _ horizon: UInt32, _ far: UInt32, _ middle: UInt32,
    _ street: UInt32, _ near: UInt32, lit: Double, lamps: Bool, stars: Double
  ) {
    skyTop = ViewColour(top)
    skyMiddle = ViewColour(middleSky)
    self.horizon = ViewColour(horizon)
    self.far = ViewColour(far)
    self.middle = ViewColour(middle)
    self.street = ViewColour(street)
    self.near = ViewColour(near)
    litShare = lit
    lampsOn = lamps
    self.stars = stars
    haze = 0
    hazeColour = ViewColour(horizon)
  }

  private mutating func apply(_ weather: ViewWeather, hour: ViewHour) {
    let isDark = hour == .night || hour == .dusk
    switch weather {
    case .clear: break
    case .rain:
      let grey = ViewColour(isDark ? 0x1C2433 : 0x7C8896)
      skyTop = skyTop.mixed(with: grey, by: 0.45)
      skyMiddle = skyMiddle.mixed(with: grey, by: 0.55)
      horizon = horizon.mixed(with: grey, by: 0.5)
      far = far.mixed(with: grey, by: 0.35)
      middle = middle.mixed(with: grey, by: 0.2)
      stars = 0
      haze = 0.35
      hazeColour = horizon
      litShare = min(1, litShare + 0.1)
    case .snow:
      // Snow cloud bounces the town's light back, so the night sky glows lilac-grey.
      let glow = ViewColour(isDark ? 0x3B3F5E : 0xC9D3E0)
      skyTop = skyTop.mixed(with: glow, by: 0.35)
      skyMiddle = skyMiddle.mixed(with: glow, by: 0.5)
      horizon = horizon.mixed(with: ViewColour(isDark ? 0x6A6F8F : 0xE8EEF4), by: 0.5)
      far = far.mixed(with: horizon, by: 0.25)
      stars *= 0.2
      haze = 0.25
      hazeColour = horizon
      litShare = min(1, litShare + 0.15)
    case .fog:
      let fog = ViewColour(isDark ? 0x34445E : 0xC5D2DE)
      skyTop = skyTop.mixed(with: fog, by: 0.3)
      skyMiddle = skyMiddle.mixed(with: fog, by: 0.6)
      horizon = horizon.mixed(with: fog, by: 0.7)
      far = far.mixed(with: fog, by: 0.75)
      middle = middle.mixed(with: fog, by: 0.45)
      street = street.mixed(with: fog, by: 0.15)
      stars = 0
      haze = 0.7
      hazeColour = fog
    }
  }

  func colour(_ plane: ViewPlane) -> ViewColour {
    switch plane {
    case .far: far
    case .middle: middle
    case .street: street
    case .near: near
    }
  }
}

/// Everything a plane's drawing depends on besides time: which view, its hour and its weather.
struct ViewLook: Hashable, Sendable {
  var view: WindowView
  var hour: ViewHour
  var weather: ViewWeather

  var palette: ViewPalette { ViewPalette(hour: hour, weather: weather, view: view) }
  var isDark: Bool { hour == .night || hour == .dusk }
}

/// The window's opening is 100 wide and `windowHeight` tall, top left at the origin. Planes are drawn wider
/// for parallax. From the room's camera the sill hides the glass below about `sillLine`: keep a street above it.
enum ViewStage {
  static let windowHeight: CGFloat = 58
  static let sillLine: CGFloat = 52
  /// What a plane covers, in stage units.
  static let plate = CGRect(x: -45, y: -50, width: 190, height: 115)

  /// Where the stage sits in the view: its unit in points and the window's top left corner.
  struct Frame: Equatable {
    var unit: CGFloat
    var origin: CGPoint

    /// From the window's outline in the view's points: its bottom edge lines up with the sill.
    init?(window: [CGPoint]) {
      guard let bounds = ViewStage.bounds(of: window), bounds.width > 1 else { return nil }
      unit = bounds.width / 100
      origin = CGPoint(x: bounds.minX, y: bounds.maxY - ViewStage.windowHeight * unit)
    }

    init(unit: CGFloat, origin: CGPoint) {
      self.unit = unit
      self.origin = origin
    }

    func point(_ stage: CGPoint) -> CGPoint {
      CGPoint(x: origin.x + stage.x * unit, y: origin.y + stage.y * unit)
    }

    /// The frame a plane is drawn in: `follow` of the way from the home frame to the live one.
    static func blend(home: Frame, live: Frame, follow: CGFloat) -> Frame {
      Frame(
        unit: home.unit + (live.unit - home.unit) * follow,
        origin: CGPoint(
          x: home.origin.x + (live.origin.x - home.origin.x) * follow,
          y: home.origin.y + (live.origin.y - home.origin.y) * follow))
    }
  }

  static func bounds(of outline: [CGPoint]) -> CGRect? {
    guard let first = outline.first else { return nil }
    return outline.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
      $0.union(CGRect(origin: $1, size: .zero))
    }
  }
}
