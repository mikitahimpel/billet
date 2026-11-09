import CoreGraphics
import Foundation
import Pet
import SwiftUI

struct DesertStars: ViewRecipe {
  static let streetBase: CGFloat = 47.6
  static let road: CGFloat = 41
  static let shooting = ViewShootingStar(
    rhythm: ViewRhythm(seed: 1301, slot: 25, chance: 0.7, length: 0.9...1.4))
  static let farCar = ViewRhythm(seed: 1311, slot: 45, chance: 0.6, length: 14...20)
  static let coyote = ViewRhythm(seed: 1321, slot: 80, chance: 0.5, length: 16...22)
  static let tumbleweed = ViewRhythm(seed: 1331, slot: 60, chance: 0.4, length: 9...13)
  static let van = CGRect(x: 52, y: 38.6, width: 22, height: 7.4)
  static let vanWindow = ViewLitWindow(
    id: 1350, rect: CGRect(x: 62.4, y: 40.2, width: 4.6, height: 2.4), plane: .street)
  static let fire = CGPoint(x: 40, y: 47.2)
  static let fairyLights = ViewLightString(
    from: CGPoint(x: 53, y: 39.2), to: CGPoint(x: 30.6, y: 37.6), sag: 1.4, count: 10,
    colours: [ViewPalette.lampCore, ViewColour(0xFFB27A), ViewColour(0xFF8AA8)], seed: 3)

  var moon: CGPoint { CGPoint(x: 78, y: -14) }
  var livePlanes: Set<ViewPlane> { [.far, .middle, .street, .near] }

  static func grade(_ palette: inout ViewPalette, hour: ViewHour, share: Double) {
    let colours: [UInt32]
    switch hour {
    case .night: colours = [0x050818, 0x121A3C, 0x2A2E5A, 0x2A2440, 0x201C34, 0x18142A, 0x0E0C1A]
    case .dusk: colours = [0x2A2458, 0x7A5A98, 0xFF9A6A, 0x8A5A6A, 0x6A4258, 0x4A3046, 0x2A1C2C]
    case .day: colours = [0x4E9AE0, 0x96CCEE, 0xF4E4C8, 0xD49A6A, 0xC88A5A, 0xA87048, 0x6A5038]
    case .morning: colours = [0x6A88C8, 0xD8B0B8, 0xFFC890, 0xC08070, 0xA06A5A, 0x80544A, 0x50383A]
    }
    palette.grade(colours, share: share)
    // Far from any town: three times the stars, and hardly a lit window.
    switch hour {
    case .night: palette.stars *= 3
    case .dusk: palette.stars *= 3.2
    case .day, .morning: break
    }
    palette.litShare *= 0.2
    if palette.haze == 0, hour == .day {
      palette.haze = 0.15
      palette.hazeColour = palette.horizon
    }
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

  private static func sand(_ colour: ViewColour, look: ViewLook) -> ViewColour {
    look.weather == .snow ? colour.mixed(with: ViewKit.snow(look), by: 0.45) : colour
  }

  // MARK: - Far: the Milky Way and the mesas

  static let mesas: [(x: CGFloat, width: CGFloat, top: CGFloat)] = [
    (-40, 30, 26), (-6, 18, 28.4), (24, 7, 30.6), (58, 34, 25), (104, 24, 27.6), (130, 20, 29),
  ]
  static let mesaBase: CGFloat = 36

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    if look.isDark, look.weather == .clear { milkyWay(context) }
    let base = Self.mesaBase
    for (index, mesa) in Self.mesas.enumerated() {
      let rock = colour.lit(index % 2 == 0 ? 0 : -0.03)
      var shape = Path()
      shape.move(to: CGPoint(x: mesa.x - 5, y: base))
      shape.addLine(to: CGPoint(x: mesa.x, y: mesa.top + 3))
      shape.addLine(to: CGPoint(x: mesa.x + 0.8, y: mesa.top))
      shape.addLine(to: CGPoint(x: mesa.x + mesa.width - 0.8, y: mesa.top))
      shape.addLine(to: CGPoint(x: mesa.x + mesa.width, y: mesa.top + 3))
      shape.addLine(to: CGPoint(x: mesa.x + mesa.width + 5, y: base))
      shape.closeSubpath()
      context.fill(shape, with: .color(rock.color()))
      var face = context
      face.clip(to: shape)
      face.fill(
        Path(
          CGRect(
            x: mesa.x + mesa.width * 0.62, y: mesa.top, width: mesa.width * 0.38 + 5,
            height: base - mesa.top)),
        with: .color(rock.lit(look.isDark ? 0.05 : 0.1).color()))
      for band in [1.6, 3.2, 5.4] as [CGFloat] {
        face.fill(
          Path(CGRect(x: mesa.x - 5, y: mesa.top + band, width: mesa.width + 10, height: 0.25)),
          with: .color(rock.lit(-0.1).color(0.7)))
      }
      if look.weather == .snow {
        ViewKit.rect(
          context, CGRect(x: mesa.x + 0.8, y: mesa.top - 0.3, width: mesa.width - 1.6, height: 0.7),
          ViewKit.snow(look), 0.85)
      }
    }
    ViewKit.ground(context, top: base - 0.4, colour: Self.sand(colour, look: look).lit(-0.02))
  }

  private func milkyWay(_ context: GraphicsContext) {
    var band = context
    band.translateBy(x: 50, y: -16)
    band.rotate(by: .degrees(20))
    var glow = band
    glow.scaleBy(x: 1, y: 0.22)
    for index in 0..<9 {
      let x = -96 + CGFloat(index) * 24
      ViewKit.glow(glow, CGPoint(x: x, y: 0), 34, ViewColour(0xB8C0FF), 0.13)
      ViewKit.glow(
        glow, CGPoint(x: x + 8, y: 6 * CGFloat(ViewRhythm.hash(index, seed: 1341) - 0.5)), 20,
        ViewColour(0xFFE0D0), 0.07)
    }
    for index in 0..<5 {
      let x = -60 + CGFloat(index) * 28
      var lane = band
      lane.scaleBy(x: 1, y: 0.1)
      ViewKit.glow(lane, CGPoint(x: x, y: 8), 16, ViewColour(0x050818), 0.25)
    }
    for index in 0..<70 {
      let along = -100 + 200 * CGFloat(ViewRhythm.hash(index, seed: 1342))
      let across = 12 * (CGFloat(ViewRhythm.hash(index, seed: 1343)) - 0.5)
      let size = 0.12 + 0.2 * CGFloat(ViewRhythm.hash(index, seed: 1344))
      ViewKit.circle(
        band, CGPoint(x: along, y: across), size, ViewColour(0xF4F6FF),
        0.5 + 0.4 * ViewRhythm.hash(index, seed: 1345))
    }
  }

  // MARK: - Middle: dunes, scrub and the road

  static let poles: [CGFloat] = [-30, -2, 26, 54, 82, 110, 138]

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let sand = Self.sand(colour, look: look)
    ViewKit.hills(
      context, base: Self.road - 0.6, waves: [2, 3.4, 1.6, 2.8, 3.6, 2, 2.6, 1.8], colour: sand)
    ViewKit.ground(context, top: Self.road - 0.8, colour: sand)
    ViewKit.rect(
      context, CGRect(x: -45, y: Self.road - 0.2, width: 190, height: 0.9),
      sand.lit(look.isDark ? -0.12 : -0.18))
    var x: CGFloat = -44
    while x < 145 {
      ViewKit.rect(
        context, CGRect(x: x, y: Self.road + 0.2, width: 1.6, height: 0.12),
        ViewColour(0xE8D8A0).mixed(with: sand, by: 0.6))
      x += 4
    }
    let pole = sand.lit(-0.3)
    for px in Self.poles {
      ViewKit.rect(context, CGRect(x: px - 0.18, y: 33.6, width: 0.36, height: 6.8), pole)
      ViewKit.rect(context, CGRect(x: px - 1.2, y: 34.2, width: 2.4, height: 0.25), pole)
    }
    for (from, to) in zip(Self.poles, Self.poles.dropFirst()) {
      ViewKit.wire(
        context, from: CGPoint(x: from, y: 34.3), to: CGPoint(x: to, y: 34.3), sag: 0.7,
        colour: pole, width: 0.1)
    }
    for index in 0..<24 {
      let bx = -40 + 180 * CGFloat(ViewRhythm.hash(index, seed: 1351))
      let by = Self.road + 1.6 + 3.4 * CGFloat(ViewRhythm.hash(index, seed: 1352))
      let r = 0.6 + 0.7 * CGFloat(ViewRhythm.hash(index, seed: 1353))
      ViewKit.circle(context, CGPoint(x: bx, y: by), r, sand.lit(-0.12))
      ViewKit.circle(context, CGPoint(x: bx + r * 0.6, y: by + 0.2), r * 0.7, sand.lit(-0.08))
    }
  }

  // MARK: - Street: the camp

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let base = Self.streetBase
    let sand = Self.sand(colour, look: look)
    var ground = Path()
    ground.move(to: CGPoint(x: -45, y: base - 0.2))
    ground.addQuadCurve(to: CGPoint(x: 145, y: base - 0.6), control: CGPoint(x: 50, y: base - 2.4))
    ground.addLine(to: CGPoint(x: 145, y: 65))
    ground.addLine(to: CGPoint(x: -45, y: 65))
    ground.closeSubpath()
    context.fill(ground, with: .color(sand.lit(0.03).color()))
    paintVan(context, colour: colour, look: look)
    ViewKit.rect(context, CGRect(x: 30.3, y: 37.4, width: 0.5, height: 9.4), colour.lit(-0.25))
    for (x, hex) in [(33.6, 0xFF8A5B), (44.6, 0x5FB8A8)] as [(CGFloat, UInt32)] {
      let cloth = ViewColour(hex).mixed(with: colour, by: look.isDark ? 0.55 : 0.25)
      let facing: CGFloat = x < Self.fire.x ? 1 : -1
      var legs = Path()
      legs.move(to: CGPoint(x: x - 1.4, y: base))
      legs.addLine(to: CGPoint(x: x + 1.4, y: base - 2))
      legs.move(to: CGPoint(x: x + 1.4, y: base))
      legs.addLine(to: CGPoint(x: x - 1.4, y: base - 2))
      context.stroke(legs, with: .color(colour.lit(-0.3).color()), lineWidth: 0.2)
      ViewKit.rect(context, CGRect(x: x - 1.6, y: base - 2.4, width: 3.2, height: 0.7), cloth)
      var back = Path()
      back.move(to: CGPoint(x: x - facing * 1.6, y: base - 2.2))
      back.addLine(to: CGPoint(x: x - facing * 2.2, y: base - 5))
      back.addLine(to: CGPoint(x: x - facing * 0.8, y: base - 5))
      back.addLine(to: CGPoint(x: x - facing * 0.4, y: base - 2.2))
      back.closeSubpath()
      context.fill(back, with: .color(cloth.lit(-0.06).color()))
    }
    let fire = Self.fire
    for index in 0..<6 {
      let angle = Double(index) / 6 * 2 * .pi
      ViewKit.circle(
        context,
        CGPoint(x: fire.x + 2 * CGFloat(cos(angle)), y: fire.y + 0.5 * CGFloat(sin(angle)) + 0.2),
        0.55, colour.lit(index % 2 == 0 ? 0.08 : 0.02))
    }
    for dx in [-1.0, 1.0] as [CGFloat] {
      var log = Path()
      log.move(to: CGPoint(x: fire.x - 1.6 * dx, y: fire.y + 0.4))
      log.addLine(to: CGPoint(x: fire.x + 1.2 * dx, y: fire.y - 0.8))
      context.stroke(
        log, with: .color(ViewColour(0x5A3A28).mixed(with: colour, by: 0.4).color()),
        lineWidth: 0.5)
    }
    let scope = CGPoint(x: 84, y: 42)
    for foot in [81.6, 84.2, 86.6] as [CGFloat] {
      var leg = Path()
      leg.move(to: scope)
      leg.addLine(to: CGPoint(x: foot, y: base - 0.4))
      context.stroke(leg, with: .color(colour.lit(-0.3).color()), lineWidth: 0.2)
    }
    var tube = context
    tube.translateBy(x: scope.x, y: scope.y - 0.3)
    tube.rotate(by: .degrees(-35))
    tube.fill(
      Path(roundedRect: CGRect(x: -2.2, y: -0.45, width: 5.4, height: 0.9), cornerRadius: 0.3),
      with: .color(ViewColour(0xE8E4DC).mixed(with: colour, by: look.isDark ? 0.6 : 0.3).color()))
  }

  private func paintVan(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let van = Self.van
    let teal = ViewColour(0x5FB8A8).mixed(with: colour, by: look.isDark ? 0.6 : 0.3)
    let cream = ViewColour(0xF2E6D0).mixed(with: colour, by: look.isDark ? 0.6 : 0.3)
    let body = Path(roundedRect: van, cornerRadius: 2.6)
    context.fill(body, with: .color(teal.color()))
    var upper = context
    upper.clip(to: body)
    upper.fill(
      Path(CGRect(x: van.minX, y: van.minY, width: van.width, height: van.height * 0.45)),
      with: .color(cream.color()))
    upper.fill(
      Path(CGRect(x: van.minX, y: van.minY + van.height * 0.45, width: van.width, height: 0.4)),
      with: .color(cream.lit(-0.1).color()))
    ViewKit.rect(
      context, CGRect(x: van.minX + 1.2, y: van.minY + 1, width: 4, height: 2.4), colour.lit(-0.3))
    ViewKit.windowFrame(context, Self.vanWindow.rect, cream)
    ViewKit.rect(
      context, CGRect(x: van.maxX - 5, y: van.minY + 3.6, width: 3.4, height: 3.6),
      teal.lit(-0.08))
    if look.weather == .snow {
      ViewKit.rect(
        context, CGRect(x: van.minX + 2, y: van.minY - 0.3, width: van.width - 4, height: 0.6),
        ViewKit.snow(look), 0.9)
    }
    for x in [van.minX + 4.4, van.maxX - 4.4] {
      ViewKit.circle(context, CGPoint(x: x, y: van.maxY + 0.4), 1.5, colour.lit(-0.45))
      ViewKit.circle(context, CGPoint(x: x, y: van.maxY + 0.4), 0.6, cream.lit(-0.2))
    }
  }

  // MARK: - Near: cactus and agave

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let cactus = colour.mixed(with: ViewColour(0x3F6A4A), by: look.isDark ? 0.12 : 0.35)
    let parts: [CGRect] = [
      CGRect(x: -0.2, y: 6, width: 4.6, height: 54),
      CGRect(x: -7, y: 28, width: 8, height: 3.2),
      CGRect(x: -7, y: 16, width: 3.2, height: 15.2),
      CGRect(x: 3.4, y: 34, width: 8, height: 3.2),
      CGRect(x: 8.2, y: 24, width: 3.2, height: 13.2),
    ]
    for part in parts {
      context.fill(
        Path(roundedRect: part, cornerRadius: min(part.width, part.height) / 2),
        with: .color(cactus.color()))
    }
    for part in [parts[0], parts[2], parts[4]] {
      ViewKit.rect(
        context,
        CGRect(
          x: part.maxX - part.width * 0.35, y: part.minY + 1.2, width: part.width * 0.2,
          height: part.height - 2.4), cactus.lit(look.isDark ? 0.05 : 0.1))
      ViewKit.rect(
        context,
        CGRect(x: part.midX - 0.1, y: part.minY + 1.2, width: 0.2, height: part.height - 2.4),
        cactus.lit(-0.12))
      if look.weather == .snow {
        ViewKit.rect(
          context, CGRect(x: part.minX + 0.4, y: part.minY, width: part.width - 0.8, height: 0.8),
          ViewKit.snow(look), 0.85)
      }
    }
    let agave = colour.mixed(with: ViewColour(0x5A8A7A), by: look.isDark ? 0.15 : 0.35)
    let root = CGPoint(x: 96, y: 60)
    for index in 0..<9 {
      let angle = -Double.pi * (0.1 + 0.8 * Double(index) / 8)
      let length: CGFloat = 7 + CGFloat(index % 3) * 2
      let tip = CGPoint(
        x: root.x + CGFloat(cos(angle)) * length * 1.2, y: root.y + CGFloat(sin(angle)) * length)
      var leaf = Path()
      leaf.move(to: CGPoint(x: root.x - 1.2, y: root.y))
      leaf.addQuadCurve(
        to: tip, control: CGPoint(x: (root.x + tip.x) / 2 - 1, y: (root.y + tip.y) / 2))
      leaf.addQuadCurve(
        to: CGPoint(x: root.x + 1.2, y: root.y),
        control: CGPoint(x: (root.x + tip.x) / 2 + 1, y: (root.y + tip.y) / 2))
      leaf.closeSubpath()
      context.fill(leaf, with: .color(agave.lit(index % 2 == 0 ? 0.04 : -0.02).color()))
    }
    let sand = Self.sand(colour, look: look)
    ViewKit.ground(context, top: 58, colour: sand)
    for (x, r) in [(20.0, 1.4), (76, 1), (82, 1.8)] as [(CGFloat, CGFloat)] {
      context.fill(
        Path(ellipseIn: CGRect(x: x - r, y: 58 - r * 0.7, width: 2 * r, height: r * 1.2)),
        with: .color(sand.lit(0.06).color()))
    }
  }
}
