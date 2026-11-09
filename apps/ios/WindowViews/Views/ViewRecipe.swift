import CoreGraphics
import Foundation
import Pet
import SwiftUI

struct ViewMoment {
  var look: ViewLook
  var palette: ViewPalette
  /// Wall-clock seconds: the life runs on it, so it never restarts with the room.
  var now: Double
  /// Seconds since the room started opening, for lights that come on with it.
  var time: Double

  init(look: ViewLook, now: Double, time: Double) {
    self.look = look
    palette = look.palette
    self.now = now
    self.time = time
  }

  /// How bright the view's electric lights are: off by day, stuttering on with the opening.
  var lamps: Double {
    palette.lampsOn ? GenzOpening.streetLamp(time) : 0
  }
}

/// A car's lights passing the window, for the room's own headlight sweep: from 0 to 1 across.
struct ViewHeadlight: Equatable {
  var progress: Double
  var leftToRight: Bool
}

/// Something outside the cat looks at, or paws at on the glass.
struct ViewInterest: Equatable {
  /// Where it is, in stage units.
  var point: CGPoint
  /// The plane it is on, for how far beyond the glass it is. `nil` is on the glass itself.
  var plane: ViewPlane?
  var paw: Bool
  /// The same for the whole of one pass, so a paw is played once per drop.
  var id: Int64
}

/// A window view drawn natively: its still planes, painted once per hour and weather into a
/// plate, and its small life, drawn every frame on top of the plane it belongs to.
protocol ViewRecipe: Sendable {
  /// The still drawing of `plane`, in stage units, over the whole of ``ViewStage/plate``.
  func paint(_ plane: ViewPlane, _ context: GraphicsContext, look: ViewLook)
  var livePlanes: Set<ViewPlane> { get }
  /// The moving things on `plane`, in stage units.
  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment)
  /// A car's lights passing, if the view has a street.
  func headlight(at now: Double) -> ViewHeadlight?
  /// What the cat would watch at `moment`, besides what the sky and the glass give.
  func interest(at moment: ViewMoment) -> ViewInterest?
  /// Where the moon hangs, in stage units.
  var moon: CGPoint { get }
}

enum ViewRecipes {
  static func recipe(for view: WindowView) -> any ViewRecipe {
    switch view {
    case .suburbNight: SuburbNight()
    case .rainySuburb: RainySuburb()
    case .snowyDecember: SnowyDecember()
    case .summerCulDeSac: SummerCulDeSac()
    case .dormQuad: DormQuad()
    case .fireEscape: FireEscape()
    case .pinkDusk: PinkDusk()
    case .sunsetBeach: SunsetBeach()
    case .forestCabin: ForestCabin()
    case .moonlitPeaks: MoonlitPeaks()
    case .neonStreet: NeonStreet()
    case .rooftopsDusk: RooftopsDusk()
    case .autumnPark: AutumnPark()
    case .mistyLake: MistyLake()
    case .desertStars: DesertStars()
    }
  }

  /// What the cat watches at `moment`: the view's own interest first, then a drop on the glass
  /// or a plane in the sky.
  static func interest(at moment: ViewMoment) -> ViewInterest? {
    recipe(for: moment.look.view).interest(at: moment)
      ?? ViewGlass.interest(at: moment) ?? ViewSky.interest(at: moment)
  }
}

/// A lit window that the life switches: whether it is lit now, from 0 to 1. Each has a mood of
/// its own from its id; now and then one goes dark for a while, or lights up, one at a time.
enum ViewWindows {
  static func level(_ window: ViewLitWindow, moment: ViewMoment) -> Double {
    let lamps = moment.palette.litShare > 0 ? moment.lamps : 0
    guard lamps > 0 else { return 0 }
    let litByMood = ViewRhythm.hash(window.id, seed: 41) < moment.palette.litShare
    let rhythm = ViewRhythm(
      seed: UInt64(window.id) &* 977 &+ 5, slot: 47, chance: 0.2, length: 14...40)
    var level = litByMood ? 1.0 : 0
    if let pass = rhythm.pass(at: moment.now) {
      let edge = min(pass.progress, 1 - pass.progress) * pass.length
      let flipped = min(edge / 0.4, 1)
      level = litByMood ? 1 - flipped : flipped
    }
    return level * lamps
  }

  /// A TV's flicker, from 0 to 1, never the same twice.
  static func flicker(_ now: Double, id: Int) -> Double {
    let a = sin(now * 3.1 + Double(id))
    let b = sin(now * 7.7 + Double(id) * 1.7)
    let c = sin(now * 13.3)
    return 0.55 + 0.25 * a * b + 0.2 * c * c
  }

  static func draw(_ windows: [ViewLitWindow], _ context: GraphicsContext, moment: ViewMoment) {
    for window in windows {
      let level = level(window, moment: moment)
      ViewKit.litWindow(
        context, window, level: level,
        flicker: window.isTV ? flicker(moment.now, id: window.id) : 1)
      if level > 0.5, window.rect.width > 2 { passer(window, context, moment: moment) }
    }
  }

  private static func passer(
    _ window: ViewLitWindow, _ context: GraphicsContext, moment: ViewMoment
  ) {
    let rhythm = ViewRhythm(
      seed: UInt64(window.id) &* 131 &+ 17, slot: 37, chance: 0.35, length: 2.4...4)
    guard let pass = rhythm.pass(at: moment.now) else { return }
    let rect = window.rect
    let p = CGFloat(pass.progress)
    let x =
      pass.variant < 0.5
      ? rect.minX - 1 + (rect.width + 2) * p : rect.maxX + 1 - (rect.width + 2) * p
    let unit = rect.height / 4.6
    var person = context
    person.clip(to: Path(rect))
    let shade = ViewColour(0x2A1A10).color(0.7)
    person.fill(
      Path(
        ellipseIn: CGRect(
          x: x - 0.7 * unit, y: rect.maxY - 3.2 * unit, width: 1.4 * unit, height: 1.5 * unit)),
      with: .color(shade))
    person.fill(
      Path(
        roundedRect: CGRect(
          x: x - 1.4 * unit, y: rect.maxY - 1.8 * unit, width: 2.8 * unit, height: 2 * unit),
        cornerRadius: 0.8 * unit),
      with: .color(shade))
  }
}
