import CoreGraphics
import Foundation
import Pet
import SwiftUI

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
    let water = Self.water(look.palette, plane: colour, isDark: look.isDark)
    let lake = CGRect(
      x: plate.minX, y: Self.shore, width: plate.width, height: plate.maxY - Self.shore)
    context.fill(
      Path(lake),
      with: .linearGradient(
        Gradient(colors: [
          look.palette.horizon.mixed(with: water, by: 0.45).color(), water.color(),
        ]), startPoint: CGPoint(x: 0, y: Self.shore), endPoint: CGPoint(x: 0, y: Self.shore + 12)))
    var mirror = context
    mirror.clip(to: Path(lake))
    mirror.opacity = 0.45
    mirror.translateBy(x: 0, y: 2 * Self.shore)
    mirror.scaleBy(x: 1, y: -1)
    farShore(mirror, colour: colour.mixed(with: water, by: 0.35), look: look)
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
    ViewKit.house(
      context, x: 78, base: deck, width: 18, wall: 8, roof: 4, colour: wood.lit(-0.04),
      look: look)
    ViewKit.windowFrame(context, Self.boathouseWindow.rect, wood)
    ViewKit.rect(context, CGRect(x: 90, y: 39.4, width: 4.4, height: 5.2), wood.lit(-0.3))
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
}
