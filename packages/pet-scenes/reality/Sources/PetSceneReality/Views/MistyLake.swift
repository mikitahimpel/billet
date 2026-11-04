import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// View 14: a lake at sunrise with mist on the water. Far: soft blue hills and a line of pines,
/// both mirrored in the still water, the sun just up and its glitter on the lake. Middle: the
/// near water with ripples, a small pine island, mist drifting across. Street: a wooden jetty
/// with a little boathouse and a moored rowboat, a grassy bank where a heron fishes. Near: reeds
/// and cattails swaying. A canoe paddles across now and then, ducks glide by in a line, and a
/// fish jumps.
struct MistyLake: ViewRecipe {
  /// Where the far shore meets the water.
  static let shore: CGFloat = 34
  static let sun = CGPoint(x: 68, y: 23)
  static let deck: CGFloat = 44.6
  static let canoe = ViewRhythm(seed: 1201, slot: 70, chance: 0.6, length: 34...48)
  static let ducks = ViewRhythm(seed: 1211, slot: 55, chance: 0.5, length: 26...36)
  static let fish = ViewRhythm(seed: 1221, slot: 14, chance: 0.5, length: 2.4...3.2)
  static let heron = ViewRhythm(seed: 1231, slot: 20, chance: 0.5, length: 3...5)
  static let heronFeet = CGPoint(x: 10, y: 47.4)
  static let lamp = ViewStreetLamp(head: CGPoint(x: 58, y: 39.4), ground: deck)
  static let boathouseWindow = ViewLitWindow(
    id: 1250, rect: CGRect(x: 84, y: 38.6, width: 3, height: 2.4), plane: .street)

  var moon: CGPoint { CGPoint(x: 26, y: -12) }
  var livePlanes: Set<ViewPlane> { [.far, .middle, .street, .near] }

  static func grade(_ palette: inout ViewPalette, hour: ViewHour, share: Double) {
    let colours: [UInt32]
    switch hour {
    case .morning: colours = [0x6E90CC, 0xE6C4D4, 0xFFCFA0, 0x9AA6C6, 0x7E8CAE, 0x5E6A84, 0x3E4A5A]
    case .day: colours = [0x5EA2DA, 0x9ACCEA, 0xE0F0F4, 0x8EAEC0, 0x6E90A8, 0x546E78, 0x3C5248]
    case .dusk: colours = [0x2E2A5E, 0x8A6AA8, 0xFFA888, 0x5E5A86, 0x4A4670, 0x343050, 0x201C34]
    case .night: colours = [0x060C1E, 0x14284A, 0x2E4E78, 0x1E3456, 0x16284A, 0x0E1C32, 0x08121E]
    }
    palette.grade(colours, share: share)
    // Few lit windows out here: a cabin or two across the water.
    palette.litShare *= 0.5
    if palette.haze == 0 {
      // The lake's own mist hangs low over the far shore, most of all at sunrise.
      palette.hazeColour = palette.horizon.mixed(with: ViewColour(0xFFFFFF), by: 0.45)
      switch hour {
      case .morning: palette.haze = 0.32
      case .day: palette.haze = 0.12
      case .dusk: palette.haze = 0.15
      case .night: palette.haze = 0.1
      }
    }
  }

  /// The colour of open water: the sky caught in it, darkened towards the plane's own colour.
  static func water(_ palette: ViewPalette, plane colour: ViewColour, isDark: Bool) -> ViewColour {
    palette.skyMiddle.mixed(with: palette.horizon, by: 0.4).mixed(
      with: colour, by: isDark ? 0.55 : 0.4)
  }

  func paint(_ plane: ViewPlane, _ context: GraphicsContext, look: ViewLook) {
    let colour = look.palette.colour(plane)
    switch plane {
    case .far: paintFar(context, colour: colour, look: look)
    case .middle: paintMiddle(context, colour: colour, look: look)
    case .street: paintStreet(context, colour: colour, look: look)
    case .near: paintNear(context, colour: colour, look: look)
    }
  }

  // MARK: - Far: hills, pines and their reflection

  private static let hillWaves: [CGFloat] = [4, 6, 3, 5, 2, 4, 3, 5]

  private func farShore(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    ViewKit.hills(
      context, base: Self.shore - 2, waves: Self.hillWaves,
      colour: colour.mixed(with: look.palette.horizon, by: 0.35))
    for index in 0..<40 {
      let x = -44 + CGFloat(index) * 4.8 + 2 * CGFloat(ViewRhythm.hash(index, seed: 1241))
      let height = 4 + 4 * CGFloat(ViewRhythm.hash(index, seed: 1242))
      ViewKit.pine(
        context, x: x, base: Self.shore + 0.2, height: height,
        colour: colour.lit(index % 3 == 0 ? 0.03 : -0.02), look: look)
    }
  }

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let plate = ViewStage.plate
    farShore(context, colour: colour, look: look)
    // The water from the far shore down, lighter at the shore where it holds the horizon.
    let water = Self.water(look.palette, plane: colour, isDark: look.isDark)
    let lake = CGRect(
      x: plate.minX, y: Self.shore, width: plate.width, height: plate.maxY - Self.shore)
    context.fill(
      Path(lake),
      with: .linearGradient(
        Gradient(colors: [
          look.palette.horizon.mixed(with: water, by: 0.45).color(), water.color(),
        ]), startPoint: CGPoint(x: 0, y: Self.shore), endPoint: CGPoint(x: 0, y: Self.shore + 12)))
    // The shore mirrored in the still water, paler than itself.
    var mirror = context
    mirror.clip(to: Path(lake))
    mirror.opacity = 0.45
    mirror.translateBy(x: 0, y: 2 * Self.shore)
    mirror.scaleBy(x: 1, y: -1)
    farShore(mirror, colour: colour.mixed(with: water, by: 0.35), look: look)
    // Fine ripple lines break the reflection up.
    for index in 0..<22 {
      let y = Self.shore + 0.6 + 9 * CGFloat(ViewRhythm.hash(index, seed: 1243))
      let x = -40 + 180 * CGFloat(ViewRhythm.hash(index, seed: 1244))
      let width = 4 + 10 * CGFloat(ViewRhythm.hash(index, seed: 1245))
      ViewKit.rect(context, CGRect(x: x, y: y, width: width, height: 0.12), water.lit(0.18), 0.6)
    }
  }

  // MARK: - Middle: the near water and the island

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let plate = ViewStage.plate
    let water = Self.water(look.palette, plane: colour, isDark: look.isDark)
    // Fades in from nothing, so the seam with the far water never shows as the planes slide.
    context.fill(
      Path(CGRect(x: plate.minX, y: 37, width: plate.width, height: plate.maxY - 37)),
      with: .linearGradient(
        Gradient(colors: [water.color(0), water.color(0.9), water.color()]),
        startPoint: CGPoint(x: 0, y: 37), endPoint: CGPoint(x: 0, y: 46)))
    // A small island of pines on the left, and its reflection.
    var island = Path()
    island.move(to: CGPoint(x: -14, y: 38.6))
    island.addQuadCurve(to: CGPoint(x: 22, y: 38.6), control: CGPoint(x: 4, y: 35.4))
    island.closeSubpath()
    context.fill(island, with: .color(colour.color()))
    for (index, x) in [-8.0, -3.4, 1.4, 6, 11.6, 16].enumerated() as EnumeratedSequence<[CGFloat]> {
      let height = 6 + 3 * CGFloat(ViewRhythm.hash(index, seed: 1246))
      ViewKit.pine(
        context, x: x, base: 37.6, height: height, colour: colour.lit(index % 2 == 0 ? 0.03 : 0),
        look: look)
      ViewKit.rect(
        context, CGRect(x: x - 1, y: 38.8, width: 2, height: height * 0.5),
        colour.mixed(with: water, by: 0.5), 0.35)
    }
    for index in 0..<26 {
      let y = 40 + 18 * CGFloat(ViewRhythm.hash(index, seed: 1247))
      let x = -40 + 180 * CGFloat(ViewRhythm.hash(index, seed: 1248))
      let width = 5 + 12 * CGFloat(ViewRhythm.hash(index, seed: 1249))
      ViewKit.rect(
        context, CGRect(x: x, y: y, width: width, height: 0.14), water.lit(0.16), 0.55)
    }
  }

  // MARK: - Street: the jetty, the boathouse and the bank

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let deck = Self.deck
    let wood = colour.mixed(with: ViewColour(0x8A5A3A), by: look.isDark ? 0.2 : 0.45)
    // The boathouse on the jetty.
    ViewKit.house(
      context, x: 78, base: deck, width: 18, wall: 8, roof: 4, colour: wood.lit(-0.04),
      look: look)
    ViewKit.windowFrame(context, Self.boathouseWindow.rect, wood)
    ViewKit.rect(context, CGRect(x: 90, y: 39.4, width: 4.4, height: 5.2), wood.lit(-0.3))
    // The jetty: planks on posts, its shadow on the water.
    ViewKit.rect(context, CGRect(x: 56, y: deck + 1.6, width: 90, height: 3), colour.lit(-0.3), 0.3)
    ViewKit.rect(context, CGRect(x: 56, y: deck, width: 90, height: 1), wood.lit(0.06))
    var x: CGFloat = 57
    while x < 146 {
      ViewKit.rect(context, CGRect(x: x, y: deck + 1, width: 0.7, height: 3.6), wood.lit(-0.18))
      ViewKit.rect(context, CGRect(x: x + 3, y: deck, width: 0.1, height: 1), wood.lit(-0.12))
      x += 6
    }
    if look.weather == .snow {
      ViewKit.rect(
        context, CGRect(x: 56, y: deck - 0.3, width: 90, height: 0.4), ViewKit.snow(look), 0.85)
    }
    // A bollard and the rowboat moored to it.
    ViewKit.rect(context, CGRect(x: 66, y: deck - 1.2, width: 0.9, height: 1.2), wood.lit(-0.2))
    let paint = ViewColour(0x4F8FA8).mixed(with: colour, by: look.isDark ? 0.6 : 0.3)
    var boat = Path()
    boat.move(to: CGPoint(x: 57.4, y: 47.2))
    boat.addLine(to: CGPoint(x: 68.6, y: 47.2))
    boat.addQuadCurve(to: CGPoint(x: 59.6, y: 49.6), control: CGPoint(x: 67, y: 49.6))
    boat.closeSubpath()
    context.fill(boat, with: .color(paint.color()))
    ViewKit.rect(context, CGRect(x: 57.4, y: 47, width: 11.2, height: 0.4), paint.lit(0.2))
    ViewKit.wire(
      context, from: CGPoint(x: 66.4, y: deck - 0.8), to: CGPoint(x: 67.8, y: 47.2), sag: 0.3,
      colour: wood.lit(-0.3), width: 0.12)
    ViewKit.streetLampPost(
      context, x: Self.lamp.head.x + 5, top: Self.lamp.head.y - 0.6, base: deck,
      colour: wood.lit(-0.25))
    // The grassy bank on the left where the heron fishes.
    var bank = Path()
    bank.move(to: CGPoint(x: -45, y: 45.6))
    bank.addQuadCurve(to: CGPoint(x: 22, y: 49.4), control: CGPoint(x: 6, y: 44.8))
    bank.addLine(to: CGPoint(x: 22, y: 65))
    bank.addLine(to: CGPoint(x: -45, y: 65))
    bank.closeSubpath()
    let grass = colour.mixed(with: ViewColour(0x4E7A4A), by: look.isDark ? 0.15 : 0.35)
    context.fill(bank, with: .color(grass.color()))
    if look.weather == .snow {
      var cap = context
      cap.clip(to: bank)
      cap.fill(
        Path(CGRect(x: -45, y: 44, width: 68, height: 2.6)),
        with: .color(ViewKit.snow(look).color(0.85)))
    }
    for index in 0..<12 {
      let x = -40 + 60 * CGFloat(ViewRhythm.hash(index, seed: 1251))
      ViewKit.circle(
        context, CGPoint(x: x, y: 47 + 2 * CGFloat(ViewRhythm.hash(index, seed: 1252))), 1.2,
        grass.lit(-0.08))
    }
  }

  // MARK: - Near: the reed bank

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    ViewKit.ground(context, top: 58, colour: colour)
    for (index, x) in [-8.0, 2, 12, 86, 96, 106].enumerated() as EnumeratedSequence<[CGFloat]> {
      context.fill(
        Path(ellipseIn: CGRect(x: x - 6, y: 56.6, width: 12, height: 3.4)),
        with: .color(colour.lit(index % 2 == 0 ? 0.03 : -0.02).color()))
    }
  }

  static let reeds: [(x: CGFloat, top: CGFloat, cattail: Bool)] = [
    (-6, 40, false), (-3, 36, true), (0, 42, false), (3, 38, true), (6, 44, false),
    (9, 39, false), (13, 45, true), (16, 47, false), (84, 46, false), (87, 41, true),
    (90, 38, false), (93, 43, true), (96, 37, false), (99, 40, true), (103, 42, false),
  ]

  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: sunrise(context, moment: moment)
    case .middle:
      glitter(context, moment: moment, from: 40, rows: 8)
      fishJump(context, moment: moment)
      rainRings(context, moment: moment)
      ducks(context, moment: moment)
      canoe(context, moment: moment)
      mist(context, moment: moment, rows: [35.6, 39.4, 43])
    case .street:
      ViewWindows.draw([Self.boathouseWindow], context, moment: moment)
      Self.lamp.draw(context, moment: moment)
      heron(context, moment: moment)
      mist(context, moment: moment, rows: [48.6])
    case .near: reeds(context, moment: moment)
    }
  }

  /// How thick the mist lies on the water, from 0 to about 1.
  static func mistiness(_ look: ViewLook) -> Double {
    let byHour: Double =
      switch look.hour {
      case .morning: 1
      case .day: 0.25
      case .dusk: 0.5
      case .night: 0.4
      }
    let byWeather: Double =
      switch look.weather {
      case .clear: 1
      case .fog: 1.25
      case .rain: 0.35
      case .snow: 0.6
      }
    return byHour * byWeather
  }

  /// Long soft bands of mist drifting slowly across the water.
  private func mist(_ context: GraphicsContext, moment: ViewMoment, rows: [CGFloat]) {
    let thick = Self.mistiness(moment.look)
    guard thick > 0.05 else { return }
    let palette = moment.palette
    let colour =
      moment.look.isDark
      ? palette.skyMiddle.lit(0.25) : palette.horizon.mixed(with: ViewColour(0xFFFFFF), by: 0.6)
    let span: CGFloat = 260
    for (row, y) in rows.enumerated() {
      for band in 0..<2 {
        let id = row * 2 + band
        let speed = 0.25 + 0.35 * ViewRhythm.hash(id, seed: 1261)
        let start = span * CGFloat(ViewRhythm.hash(id, seed: 1262))
        let x =
          (start + CGFloat(moment.now * speed)).truncatingRemainder(dividingBy: span) - 80
        var mist = context
        mist.translateBy(x: x, y: y + CGFloat(sin(moment.now * 0.05 + Double(id))) * 0.6)
        mist.scaleBy(x: 1, y: 0.12)
        ViewKit.glow(mist, .zero, 36, colour, 0.32 * thick)
      }
    }
  }

  /// The sun just up over the hills at sunrise or low at dusk, or the moon's light at night, and
  /// its glitter on the far water.
  private func sunrise(_ context: GraphicsContext, moment: ViewMoment) {
    let hour = moment.look.hour
    guard moment.look.weather != .rain else { return }
    let dim = moment.look.weather == .clear ? 1.0 : 0.45
    if hour == .morning || hour == .dusk {
      let sun = Self.sun
      ViewKit.glow(context, sun, 24, ViewColour(0xFFD8A0), 0.5 * dim)
      ViewKit.circle(context, sun, 3.2, ViewColour(0xFFF0D0), 0.95 * dim)
    }
    glitter(context, moment: moment, from: Self.shore + 0.6, rows: 7)
  }

  /// Short bright dashes on the water under the sun, or the moon at night, twinkling.
  private func glitter(
    _ context: GraphicsContext, moment: ViewMoment, from top: CGFloat, rows: Int
  ) {
    let hour = moment.look.hour
    guard moment.look.weather == .clear || moment.look.weather == .fog else { return }
    let x: CGFloat
    let colour: ViewColour
    let alpha: Double
    switch hour {
    case .morning, .dusk:
      x = Self.sun.x
      colour = ViewColour(0xFFE6B8)
      alpha = 0.75
    case .night:
      x = moon.x
      colour = ViewColour(0xDDE6FF)
      alpha = 0.4
    case .day:
      x = Self.sun.x
      colour = ViewColour(0xFFFFFF)
      alpha = 0.35
    }
    for row in 0..<rows {
      let y = top + CGFloat(row) * 1.1
      let width = 1.4 + CGFloat(row) * 0.7
      for dash in 0..<2 {
        let id = row * 2 + dash
        let speed = 1.5 + 3 * ViewRhythm.hash(id, seed: 1263)
        let flicker = 0.5 + 0.5 * sin(moment.now * speed + Double(id) * 1.7)
        let shift = (CGFloat(ViewRhythm.hash(id, seed: 1264)) - 0.5) * width * 1.6
        ViewKit.rect(
          context, CGRect(x: x + shift - width / 2, y: y, width: width, height: 0.22), colour,
          alpha * flicker)
      }
    }
  }

  static func canoePoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    let p = CGFloat(pass.progress)
    let x = pass.variant < 0.5 ? -25 + 150 * p : 125 - 150 * p
    return CGPoint(x: x, y: 42 + 3 * CGFloat(pass.variant))
  }

  /// A canoe paddled slowly across, a little wake behind it.
  private func canoe(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = Self.canoe.pass(at: moment.now) else { return }
    let point = Self.canoePoint(pass)
    let facing: CGFloat = pass.variant < 0.5 ? 1 : -1
    let isDark = moment.look.isDark
    let palette = moment.palette
    let hull = palette.middle.lit(-0.2).mixed(with: ViewColour(0xD0683A), by: isDark ? 0.2 : 0.55)
    let wake = Self.water(palette, plane: palette.middle, isDark: isDark).lit(0.22)
    for step in 1...3 {
      let back = CGFloat(step) * 2.6
      let spread = CGFloat(step) * 0.45
      for side in [-1.0, 1.0] as [CGFloat] {
        var line = Path()
        line.move(to: CGPoint(x: point.x - facing * (4 + back), y: point.y + 0.5 + side * spread))
        line.addLine(
          to: CGPoint(x: point.x - facing * (5.6 + back), y: point.y + 0.5 + side * spread * 1.3))
        context.stroke(
          line, with: .color(wake.color(0.5 - 0.12 * Double(step))), lineWidth: 0.14)
      }
    }
    // Its reflection, then the hull.
    context.fill(
      Path(ellipseIn: CGRect(x: point.x - 5, y: point.y + 0.4, width: 10, height: 1.6)),
      with: .color(hull.lit(-0.3).color(0.3)))
    var boat = Path()
    boat.move(to: CGPoint(x: point.x - 5.2, y: point.y - 1))
    boat.addQuadCurve(
      to: CGPoint(x: point.x + 5.2, y: point.y - 1), control: CGPoint(x: point.x, y: point.y + 1.6))
    boat.closeSubpath()
    context.fill(boat, with: .color(hull.color()))
    // The paddler, in a yellow jacket, and the paddle dipping on one side.
    let jacket = ViewColour(0xFFC24A).mixed(with: palette.middle, by: isDark ? 0.6 : 0.25)
    context.fill(
      Path(
        roundedRect: CGRect(x: point.x - 0.8, y: point.y - 3.8, width: 1.6, height: 3),
        cornerRadius: 0.6),
      with: .color(jacket.color()))
    ViewKit.circle(
      context, CGPoint(x: point.x, y: point.y - 4.5), 0.75, palette.middle.lit(-0.35))
    let stroke = CGFloat(sin(moment.now * 1.6))
    var paddle = Path()
    paddle.move(to: CGPoint(x: point.x + facing * 0.6, y: point.y - 3.4))
    let blade = CGPoint(x: point.x - facing * (1.2 + 1.6 * stroke), y: point.y + 0.6)
    paddle.addLine(to: blade)
    context.stroke(paddle, with: .color(hull.lit(-0.35).color()), lineWidth: 0.25)
    if stroke > 0.7 {
      context.stroke(
        Path(ellipseIn: CGRect(x: blade.x - 1, y: blade.y - 0.2, width: 2, height: 0.5)),
        with: .color(wake.color(0.45)), lineWidth: 0.12)
    }
  }

  static func duckPoint(_ pass: ViewRhythm.Pass, duck: Int) -> CGPoint {
    let p = CGFloat(pass.progress)
    let leftToRight = pass.variant < 0.5
    let lead = leftToRight ? -15 + 130 * p : 115 - 130 * p
    let x = lead - (leftToRight ? 1 : -1) * CGFloat(duck) * 2.6
    return CGPoint(x: x, y: 47.6 + CGFloat(duck % 2) * 0.4)
  }

  /// A mother duck and her ducklings gliding by in a line, while it is light.
  private func ducks(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.hour != .night, let pass = Self.ducks.pass(at: moment.now) else { return }
    let facing: CGFloat = pass.variant < 0.5 ? 1 : -1
    let brown = ViewColour(0x7A5A3A).mixed(
      with: moment.palette.middle, by: moment.look.isDark ? 0.5 : 0.2)
    let beak = ViewColour(0xF0A040).mixed(with: brown, by: 0.2)
    for duck in 0..<4 {
      let point = Self.duckPoint(pass, duck: duck)
      let size: CGFloat = duck == 0 ? 1 : 0.6
      let bob = CGFloat(sin(moment.now * 2.2 + Double(duck))) * 0.12
      context.fill(
        Path(
          ellipseIn: CGRect(
            x: point.x - 1.1 * size, y: point.y - 0.8 * size + bob, width: 2.2 * size,
            height: 0.9 * size)),
        with: .color(brown.color()))
      let head = CGPoint(x: point.x + facing * 0.9 * size, y: point.y - 1.2 * size + bob)
      ViewKit.circle(context, head, 0.45 * size, brown.lit(duck == 0 ? -0.15 : 0.1))
      ViewKit.rect(
        context,
        CGRect(
          x: head.x + (facing > 0 ? 0.3 : -0.8) * size, y: head.y - 0.05, width: 0.5 * size,
          height: 0.2 * size), beak)
      ViewKit.rect(
        context,
        CGRect(x: point.x - 1.6 * size, y: point.y + 0.2, width: 3.2 * size, height: 0.1),
        moment.palette.horizon, 0.35)
    }
  }

  static func fishPoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    let id = Int(pass.index % 10_000)
    return CGPoint(
      x: 14 + 60 * CGFloat(ViewRhythm.hash(id, seed: 1271)),
      y: 40 + 8 * CGFloat(ViewRhythm.hash(id, seed: 1272)))
  }

  /// A fish jumping: a quick arc out of the water, then rings spreading where it went back in.
  private func fishJump(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.weather != .rain, let pass = Self.fish.pass(at: moment.now) else { return }
    let point = Self.fishPoint(pass)
    let p = CGFloat(pass.progress)
    let ring = Self.water(moment.palette, plane: moment.palette.middle, isDark: moment.look.isDark)
      .lit(0.3)
    if p < 0.18 {
      let arc = p / 0.18
      let fish = CGPoint(x: point.x - 1 + 2 * arc, y: point.y - 2.4 * sin(arc * .pi))
      context.fill(
        Path(ellipseIn: CGRect(x: fish.x - 0.6, y: fish.y - 0.25, width: 1.2, height: 0.5)),
        with: .color(ring.color(0.9)))
    }
    for wave in 0..<2 {
      let local = p - 0.15 - CGFloat(wave) * 0.2
      guard local > 0 else { continue }
      let radius = 0.6 + 4 * local
      context.stroke(
        Path(
          ellipseIn: CGRect(
            x: point.x + 1 - radius, y: point.y - radius * 0.25, width: 2 * radius,
            height: radius * 0.5)),
        with: .color(ring.color(0.6 * Double(1 - local))), lineWidth: 0.14)
    }
  }

  /// Rings from raindrops landing all over the lake.
  private func rainRings(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.weather == .rain else { return }
    let ring = Self.water(moment.palette, plane: moment.palette.middle, isDark: moment.look.isDark)
      .lit(0.25)
    for index in 0..<12 {
      let period = 1 + 0.6 * ViewRhythm.hash(index, seed: 1281)
      let cycle = moment.now / period + ViewRhythm.hash(index, seed: 1282)
      let p = CGFloat(cycle - cycle.rounded(.down))
      let slot = Int(cycle.rounded(.down)) % 997
      let x = -4 + 108 * CGFloat(ViewRhythm.hash(index * 1000 + slot, seed: 1283))
      let y = 39 + 14 * CGFloat(ViewRhythm.hash(index * 1000 + slot, seed: 1284))
      let radius = 0.3 + 1.8 * p
      context.stroke(
        Path(
          ellipseIn: CGRect(
            x: x - radius, y: y - radius * 0.3, width: 2 * radius, height: radius * 0.6)),
        with: .color(ring.color(0.55 * Double(1 - p))), lineWidth: 0.12)
    }
  }

  /// The heron standing in the shallows, now and then striking down at a fish.
  private func heron(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.hour != .night else { return }
    let feet = Self.heronFeet
    let grey = ViewColour(0x8A96A8).mixed(
      with: moment.palette.street, by: moment.look.isDark ? 0.55 : 0.3)
    var dip: CGFloat = 0
    if let pass = Self.heron.pass(at: moment.now) {
      dip = CGFloat(sin(pass.progress * .pi))
    }
    for dx in [-0.3, 0.4] as [CGFloat] {
      var leg = Path()
      leg.move(to: CGPoint(x: feet.x + dx, y: feet.y))
      leg.addLine(to: CGPoint(x: feet.x + dx * 0.5, y: feet.y - 3.6))
      context.stroke(leg, with: .color(grey.lit(-0.3).color()), lineWidth: 0.16)
    }
    let body = CGPoint(x: feet.x, y: feet.y - 4.4)
    var bodyPath = Path()
    bodyPath.move(to: CGPoint(x: body.x - 1.8, y: body.y + 0.6))
    bodyPath.addQuadCurve(
      to: CGPoint(x: body.x + 1.4, y: body.y - 0.8),
      control: CGPoint(x: body.x - 0.6, y: body.y - 1.4)
    )
    bodyPath.addQuadCurve(
      to: CGPoint(x: body.x - 1.8, y: body.y + 0.6),
      control: CGPoint(x: body.x + 0.6, y: body.y + 1))
    context.fill(bodyPath, with: .color(grey.color()))
    // The neck: up in an S while it waits, down and forward when it strikes.
    let head = CGPoint(x: body.x + 1.8 + 1.4 * dip, y: body.y - 3.4 + 5.4 * dip)
    var neck = Path()
    neck.move(to: CGPoint(x: body.x + 1.2, y: body.y - 0.6))
    neck.addQuadCurve(to: head, control: CGPoint(x: body.x + 0.4 + 2 * dip, y: body.y - 2))
    context.stroke(neck, with: .color(grey.color()), lineWidth: 0.45)
    ViewKit.circle(context, head, 0.5, grey.lit(0.08))
    var beak = Path()
    beak.move(to: CGPoint(x: head.x + 0.3, y: head.y))
    beak.addLine(to: CGPoint(x: head.x + 2, y: head.y + 0.3 + 0.8 * dip))
    context.stroke(
      beak, with: .color(ViewColour(0xD8A040).mixed(with: grey, by: 0.3).color()), lineWidth: 0.2)
  }

  /// Reeds and cattails at the water's edge, bending with the breeze.
  private func reeds(_ context: GraphicsContext, moment: ViewMoment) {
    let wind = moment.look.weather == .rain ? 1.8 : 1
    let t = moment.now
    let colour = moment.palette.near
    let cattail = ViewColour(0x6A4A30).mixed(with: colour, by: moment.look.isDark ? 0.6 : 0.3)
    for (index, reed) in Self.reeds.enumerated() {
      let sway =
        CGFloat(
          (0.6 * sin(t * 0.8 + Double(index) * 0.7) + 0.3 * sin(t * 2.1 + Double(index)))
            * wind) * 1.4
      let base = CGPoint(x: reed.x, y: 59)
      let tip = CGPoint(x: reed.x + sway + (index % 2 == 0 ? 1 : -1), y: reed.top)
      let control = CGPoint(x: reed.x + sway * 0.3, y: (base.y + reed.top) / 2)
      var leaf = Path()
      leaf.move(to: CGPoint(x: base.x - 0.4, y: base.y))
      leaf.addQuadCurve(to: tip, control: control)
      leaf.addQuadCurve(to: CGPoint(x: base.x + 0.4, y: base.y), control: control)
      leaf.closeSubpath()
      context.fill(leaf, with: .color(colour.lit(index % 3 == 0 ? 0.05 : -0.02).color()))
      if reed.cattail {
        let head = CGPoint(x: tip.x - sway * 0.08, y: reed.top + 3.4)
        context.fill(
          Path(
            roundedRect: CGRect(x: head.x - 0.55, y: head.y - 1.8, width: 1.1, height: 3.6),
            cornerRadius: 0.55),
          with: .color(cattail.color()))
        if moment.look.weather == .snow {
          ViewKit.rect(
            context, CGRect(x: head.x - 0.55, y: head.y - 1.9, width: 1.1, height: 0.5),
            ViewKit.snow(moment.look), 0.85)
        }
      }
    }
  }

  func headlight(at now: Double) -> ViewHeadlight? { nil }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if let pass = Self.canoe.pass(at: moment.now) {
      let point = Self.canoePoint(pass)
      if point.x > 0, point.x < 100 {
        return ViewInterest(point: point, plane: .middle, paw: false, id: pass.index)
      }
    }
    if moment.look.hour != .night, let pass = Self.ducks.pass(at: moment.now) {
      let point = Self.duckPoint(pass, duck: 0)
      if point.x > 0, point.x < 100 {
        return ViewInterest(point: point, plane: .middle, paw: false, id: pass.index)
      }
    }
    if moment.look.weather != .rain, let pass = Self.fish.pass(at: moment.now) {
      return ViewInterest(point: Self.fishPoint(pass), plane: .middle, paw: false, id: pass.index)
    }
    if moment.look.hour != .night, let pass = Self.heron.pass(at: moment.now) {
      return ViewInterest(
        point: CGPoint(x: Self.heronFeet.x + 2, y: Self.heronFeet.y - 4), plane: .street,
        paw: false, id: pass.index)
    }
    return nil
  }
}
