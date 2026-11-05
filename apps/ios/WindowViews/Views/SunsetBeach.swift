import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// View 8: a beach at sunset. Far: the sea to the horizon with a hazy island, the low sun and its
/// glitter path on the water, a sailboat sliding along the horizon now and then. Middle: a
/// headland with a lighthouse whose beam sweeps after dark, and a pier on stilts with its lamps.
/// Street: the sand, gentle waves running up it and slipping back, a beach shack with its window
/// lit, string lights over to the lifeguard tower, an umbrella and a towel, someone walking a dog
/// along the water. Near: a dune with grass moving in the breeze and a rope fence. Gulls glide
/// over while it is light.
struct SunsetBeach: ViewRecipe {
  static let horizon: CGFloat = 30
  static let shore: CGFloat = 44
  static let sun = CGPoint(x: 38, y: 27)
  static let lighthouse = CGPoint(x: 4, y: 12.8)
  static let pierLamps: [CGPoint] = [CGPoint(x: 96, y: 31.4), CGPoint(x: 118, y: 31.4)]
  static let tower = CGRect(x: 66, y: 35.6, width: 9.4, height: 5)
  static let shack = CGRect(x: 3, y: 38, width: 15, height: 8.4)
  static let flag = CGPoint(x: 74.6, y: 29.4)
  static let boat = ViewRhythm(seed: 801, slot: 70, chance: 0.6, length: 45...62)
  static let gulls = ViewRhythm(seed: 811, slot: 34, chance: 0.6, length: 10...14)
  static let walker = ViewWalker(
    rhythm: ViewRhythm(seed: 821, slot: 45, chance: 0.55, length: 14...20),
    from: CGPoint(x: -20, y: 49.4), to: CGPoint(x: 120, y: 49.4), height: 5.6,
    kinds: [.dog, .walker, .phone, .dog], coats: [0xF2F0EA, 0xFF8A5B, 0x5FB7B0, 0xE0B04A])
  static let shackWindow = ViewLitWindow(
    id: 1701, rect: CGRect(x: 6, y: 40.6, width: 9, height: 2.6), plane: .street)

  var moon: CGPoint { CGPoint(x: 72, y: -10) }
  var livePlanes: Set<ViewPlane> { [.far, .middle, .street, .near] }

  /// The beach's own colours: a warm sea at sunset, a deep blue one at night.
  static func grade(_ palette: inout ViewPalette, hour: ViewHour, share: Double) {
    let colours: [UInt32]
    switch hour {
    case .dusk: colours = [0x2E2A64, 0xD86A8E, 0xFFB27A, 0x6A5A8E, 0x4A3A6A, 0x3A2C52, 0x22183A]
    case .night: colours = [0x080C22, 0x1C2A52, 0x3A4A7A, 0x2A3A64, 0x1C2848, 0x162038, 0x0C1222]
    case .day: colours = [0x4AA8E0, 0x8ED0F0, 0xE6F4F8, 0x4A9AC0, 0x7A8A8A, 0xC8B48E, 0x7A8A5E]
    case .morning:
      colours = [0x7A90D0, 0xF0C0C8, 0xFFD8B0, 0x8AA0C8, 0x8A88A0, 0xB8A48A, 0x6A7060]
    }
    palette.grade(colours, share: share)
    if palette.haze == 0 {
      palette.hazeColour = palette.horizon
      palette.haze = hour == .day ? 0.15 : 0.08
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

  static func sand(_ colour: ViewColour, look: ViewLook) -> ViewColour {
    let sand = colour.mixed(with: ViewColour(0xE8C8A0), by: look.isDark ? 0.2 : 0.45)
    return look.weather == .snow ? sand.mixed(with: ViewKit.snow(look), by: 0.5) : sand
  }

  // MARK: - Far: the sea

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let palette = look.palette
    let plate = ViewStage.plate
    let horizon = Self.horizon
    // A hazy island on the horizon, clear of the sun.
    var island = Path()
    island.move(to: CGPoint(x: 62, y: horizon + 0.2))
    island.addQuadCurve(
      to: CGPoint(x: 78, y: horizon - 2.6), control: CGPoint(x: 69, y: horizon - 3.4))
    island.addQuadCurve(
      to: CGPoint(x: 94, y: horizon + 0.2), control: CGPoint(x: 87, y: horizon - 2.4))
    island.closeSubpath()
    context.fill(island, with: .color(colour.mixed(with: palette.horizon, by: 0.35).color()))
    // The sea: holding the sky's light at the horizon, deeper towards the shore.
    let sea = CGRect(
      x: plate.minX, y: horizon, width: plate.width, height: plate.maxY - horizon)
    context.fill(
      Path(sea),
      with: .linearGradient(
        Gradient(colors: [
          palette.horizon.mixed(with: colour, by: 0.55).color(), colour.color(),
          colour.lit(-0.12).color(),
        ]), startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: Self.shore + 4)))
    // Swell lines, closer together far off.
    for index in 0..<18 {
      let share = CGFloat(index) / 18
      let y = horizon + 0.8 + share * share * 13
      let x = plate.minX + plate.width * CGFloat(ViewRhythm.hash(index, seed: 833))
      let width = 14 + 30 * CGFloat(ViewRhythm.hash(index, seed: 834))
      ViewKit.rect(
        context, CGRect(x: x - width / 2, y: y, width: width, height: 0.12 + share * 0.15),
        colour.lit(0.14), 0.45)
    }
  }

  // MARK: - Middle: the headland and the pier

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    var land = Path()
    land.move(to: CGPoint(x: -45, y: 65))
    land.addLine(to: CGPoint(x: -45, y: 22))
    land.addQuadCurve(to: CGPoint(x: 2, y: 23.6), control: CGPoint(x: -24, y: 18))
    land.addQuadCurve(to: CGPoint(x: 16, y: 37), control: CGPoint(x: 12, y: 26))
    land.addLine(to: CGPoint(x: 24, y: 42))
    land.addLine(to: CGPoint(x: 24, y: 65))
    land.closeSubpath()
    context.fill(land, with: .color(colour.color()))
    // The lit slope facing the sun.
    var lit = Path()
    lit.move(to: CGPoint(x: 2, y: 23.6))
    lit.addQuadCurve(to: CGPoint(x: 16, y: 37), control: CGPoint(x: 12, y: 26))
    lit.addLine(to: CGPoint(x: 12, y: 37))
    lit.addQuadCurve(to: CGPoint(x: 0, y: 25), control: CGPoint(x: 8, y: 27))
    lit.closeSubpath()
    context.fill(lit, with: .color(colour.lit(look.isDark ? 0.06 : 0.12).color()))
    for index in 0..<6 {
      let x = 14 + CGFloat(index) * 2.2
      ViewKit.circle(
        context, CGPoint(x: x, y: 41 + CGFloat(index % 2) * 0.6),
        1.2 + 0.5 * CGFloat(ViewRhythm.hash(index, seed: 841)), colour.lit(-0.08))
    }
    if look.weather == .snow {
      var cap = Path()
      cap.move(to: CGPoint(x: -45, y: 22))
      cap.addQuadCurve(to: CGPoint(x: 2, y: 23.6), control: CGPoint(x: -24, y: 18))
      cap.addLine(to: CGPoint(x: 2, y: 24.8))
      cap.addQuadCurve(to: CGPoint(x: -45, y: 23.4), control: CGPoint(x: -24, y: 19.4))
      cap.closeSubpath()
      context.fill(cap, with: .color(ViewKit.snow(look).color(0.85)))
    }
    // The lighthouse: a tapering white tower with red bands, the lamp room and a cap.
    let paint = colour.mixed(with: ViewColour(0xF0E8E0), by: look.isDark ? 0.18 : 0.45)
    let band = colour.mixed(with: ViewColour(0xD8504A), by: look.isDark ? 0.25 : 0.5)
    let x = Self.lighthouse.x
    var tower = Path()
    tower.move(to: CGPoint(x: x - 1.7, y: 24))
    tower.addLine(to: CGPoint(x: x - 1.1, y: 14.4))
    tower.addLine(to: CGPoint(x: x + 1.1, y: 14.4))
    tower.addLine(to: CGPoint(x: x + 1.7, y: 24))
    tower.closeSubpath()
    context.fill(tower, with: .color(paint.color()))
    var banded = context
    banded.clip(to: tower)
    for y in [16.4, 20.2] as [CGFloat] {
      ViewKit.rect(banded, CGRect(x: x - 2, y: y, width: 4, height: 1.6), band)
    }
    ViewKit.rect(banded, CGRect(x: x + 0.3, y: 14, width: 1.6, height: 10), paint.lit(-0.1), 0.5)
    ViewKit.rect(context, CGRect(x: x - 1.6, y: 14, width: 3.2, height: 0.5), colour.lit(-0.2))
    ViewKit.rect(context, CGRect(x: x - 0.9, y: 12, width: 1.8, height: 2), colour.lit(-0.25))
    var cap = Path()
    cap.move(to: CGPoint(x: x - 1.2, y: 12))
    cap.addLine(to: CGPoint(x: x, y: 10.6))
    cap.addLine(to: CGPoint(x: x + 1.2, y: 12))
    cap.closeSubpath()
    context.fill(cap, with: .color(band.lit(-0.15).color()))
    // The pier on stilts, running out from the right.
    let deck: CGFloat = 36
    let wood = colour.lit(-0.1)
    ViewKit.rect(context, CGRect(x: 84, y: deck, width: 61, height: 0.9), wood)
    var post: CGFloat = 85
    while post < 145 {
      ViewKit.rect(context, CGRect(x: post, y: deck + 0.9, width: 0.5, height: 5), wood.lit(-0.1))
      ViewKit.rect(context, CGRect(x: post, y: deck - 1.6, width: 0.3, height: 1.6), wood)
      post += 3.6
    }
    ViewKit.rect(context, CGRect(x: 84, y: deck - 1.6, width: 61, height: 0.2), wood)
    for lamp in Self.pierLamps {
      ViewKit.rect(
        context, CGRect(x: lamp.x - 0.2, y: lamp.y, width: 0.4, height: deck - lamp.y), wood)
    }
  }

  // MARK: - Street: the sand

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let base = Self.shore
    let sand = Self.sand(colour, look: look)
    // Wet sand along the water, then the dry beach.
    ViewKit.rect(context, CGRect(x: -45, y: base, width: 190, height: 3.4), sand.lit(-0.14))
    ViewKit.ground(context, top: base + 3.4, colour: sand)
    for index in 0..<14 {
      let x = -40 + 180 * CGFloat(ViewRhythm.hash(index, seed: 851))
      let y = base + 4.4 + 8 * CGFloat(ViewRhythm.hash(index, seed: 852))
      ViewKit.rect(
        context, CGRect(x: x, y: y, width: 5 + CGFloat(index % 3) * 2, height: 0.15),
        sand.lit(0.08), 0.7)
    }
    // The beach shack: a plank box, its counter window under a thatched roof.
    let shack = Self.shack
    let planks = colour.mixed(with: ViewColour(0xB07A50), by: look.isDark ? 0.2 : 0.45)
    ViewKit.rect(context, shack, planks)
    var plank = shack.minX + 1.6
    while plank < shack.maxX {
      ViewKit.rect(
        context, CGRect(x: plank, y: shack.minY, width: 0.1, height: shack.height),
        planks.lit(-0.12), 0.8)
      plank += 1.6
    }
    ViewKit.windowFrame(context, Self.shackWindow.rect, planks)
    var thatch = Path()
    thatch.move(to: CGPoint(x: shack.minX - 2, y: shack.minY + 0.6))
    thatch.addLine(to: CGPoint(x: shack.midX, y: shack.minY - 3.4))
    thatch.addLine(to: CGPoint(x: shack.maxX + 2, y: shack.minY + 0.6))
    thatch.closeSubpath()
    let straw = colour.mixed(with: ViewColour(0xD8B070), by: look.isDark ? 0.18 : 0.4)
    context.fill(thatch, with: .color(straw.color()))
    for index in 0..<9 {
      let x = shack.minX - 1.6 + CGFloat(index) * 2.3
      ViewKit.rect(
        context, CGRect(x: x, y: shack.minY - 0.2, width: 0.18, height: 0.9), straw.lit(-0.15))
    }
    if look.weather == .snow {
      var cap = Path()
      cap.move(to: CGPoint(x: shack.minX - 1, y: shack.minY - 0.2))
      cap.addLine(to: CGPoint(x: shack.midX, y: shack.minY - 3.4))
      cap.addLine(to: CGPoint(x: shack.maxX + 1, y: shack.minY - 0.2))
      cap.addLine(to: CGPoint(x: shack.midX, y: shack.minY - 2.2))
      cap.closeSubpath()
      context.fill(cap, with: .color(ViewKit.snow(look).color(0.85)))
    }
    // The lifeguard tower: a hut on stilts with a ramp down to the sand.
    let tower = Self.tower
    let teal = colour.mixed(with: ViewColour(0x5FB7B0), by: look.isDark ? 0.25 : 0.55)
    let legs = colour.lit(-0.15)
    for (top, foot) in [(tower.minX + 1, tower.minX - 0.4), (tower.maxX - 1, tower.maxX + 0.4)] {
      var leg = Path()
      leg.move(to: CGPoint(x: top, y: tower.maxY))
      leg.addLine(to: CGPoint(x: foot, y: base + 4))
      context.stroke(leg, with: .color(legs.color()), lineWidth: 0.6)
    }
    var brace = Path()
    brace.move(to: CGPoint(x: tower.minX + 0.4, y: tower.maxY + 1.4))
    brace.addLine(to: CGPoint(x: tower.maxX - 0.4, y: base + 2))
    context.stroke(brace, with: .color(legs.color()), lineWidth: 0.25)
    var ramp = Path()
    ramp.move(to: CGPoint(x: tower.minX, y: tower.maxY + 0.2))
    ramp.addLine(to: CGPoint(x: tower.minX - 6, y: base + 4))
    context.stroke(ramp, with: .color(legs.lit(0.06).color()), lineWidth: 0.7)
    ViewKit.rect(context, tower, teal)
    ViewKit.rect(
      context, CGRect(x: tower.minX + 1.4, y: tower.minY + 1, width: tower.width - 2.8, height: 2),
      teal.lit(-0.3))
    ViewKit.rect(
      context, CGRect(x: tower.minX, y: tower.maxY - 0.6, width: tower.width, height: 0.6),
      teal.lit(-0.12))
    var roof = Path()
    roof.move(to: CGPoint(x: tower.minX - 1.2, y: tower.minY))
    roof.addLine(to: CGPoint(x: tower.minX + 1, y: tower.minY - 1.6))
    roof.addLine(to: CGPoint(x: tower.maxX - 1, y: tower.minY - 1.6))
    roof.addLine(to: CGPoint(x: tower.maxX + 1.2, y: tower.minY))
    roof.closeSubpath()
    context.fill(roof, with: .color(teal.lit(look.isDark ? 0.04 : 0.15).color()))
    ViewKit.rect(
      context,
      CGRect(
        x: Self.flag.x - 0.15, y: Self.flag.y, width: 0.3, height: tower.minY - Self.flag.y - 1.6),
      legs)
    // A striped umbrella and a towel.
    let pole = CGPoint(x: 32, y: base + 5)
    ViewKit.rect(context, CGRect(x: pole.x - 0.15, y: base - 4, width: 0.3, height: 9), legs)
    var dome = Path()
    dome.move(to: CGPoint(x: pole.x - 6, y: base - 3.4))
    dome.addQuadCurve(
      to: CGPoint(x: pole.x + 6, y: base - 3.4), control: CGPoint(x: pole.x, y: base - 9.4))
    dome.closeSubpath()
    let coral = colour.mixed(with: ViewColour(0xFF7A6A), by: look.isDark ? 0.3 : 0.6)
    let cream = colour.mixed(with: ViewColour(0xF6EEDC), by: look.isDark ? 0.25 : 0.6)
    context.fill(dome, with: .color(cream.color()))
    var stripes = context
    stripes.clip(to: dome)
    for index in 0..<3 {
      ViewKit.rect(
        stripes, CGRect(x: pole.x - 6 + CGFloat(index) * 4.4, y: base - 10, width: 2.2, height: 7),
        coral)
    }
    var towel = Path()
    towel.move(to: CGPoint(x: pole.x + 1, y: base + 5.4))
    towel.addLine(to: CGPoint(x: pole.x + 9, y: base + 5.4))
    towel.addLine(to: CGPoint(x: pole.x + 8, y: base + 7))
    towel.addLine(to: CGPoint(x: pole.x, y: base + 7))
    towel.closeSubpath()
    context.fill(
      towel,
      with: .color(colour.mixed(with: ViewColour(0x7AB0E0), by: look.isDark ? 0.3 : 0.6).color()))
    var towelStripes = context
    towelStripes.clip(to: towel)
    for x in [pole.x + 3, pole.x + 6] {
      ViewKit.rect(towelStripes, CGRect(x: x, y: base + 5, width: 0.8, height: 3), cream)
    }
  }

  // MARK: - Near: the dune

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let sand = colour.mixed(with: ViewColour(0xE8C8A0), by: look.isDark ? 0.14 : 0.32)
    var dune = Path()
    dune.move(to: CGPoint(x: -45, y: 65))
    dune.addLine(to: CGPoint(x: -45, y: 54))
    dune.addQuadCurve(to: CGPoint(x: 40, y: 58), control: CGPoint(x: 5, y: 50))
    dune.addQuadCurve(to: CGPoint(x: 145, y: 57), control: CGPoint(x: 100, y: 60))
    dune.addLine(to: CGPoint(x: 145, y: 65))
    dune.closeSubpath()
    context.fill(
      dune,
      with: .color(
        (look.weather == .snow ? sand.mixed(with: ViewKit.snow(look), by: 0.45) : sand).color()))
    ViewKit.ground(context, top: 59, colour: sand.lit(-0.04))
    // A rope fence on weathered posts.
    let wood = colour.lit(0.05)
    for x in [86, 104] as [CGFloat] {
      ViewKit.rect(context, CGRect(x: x, y: 45, width: 1.4, height: 17), wood)
      ViewKit.rect(context, CGRect(x: x + 0.8, y: 45, width: 0.6, height: 17), wood.lit(0.08))
    }
    let rope = colour.mixed(with: ViewColour(0xD8B070), by: look.isDark ? 0.2 : 0.4)
    ViewKit.wire(
      context, from: CGPoint(x: 86.7, y: 47), to: CGPoint(x: 104.7, y: 47.6), sag: 1.4,
      colour: rope, width: 0.35)
    ViewKit.wire(
      context, from: CGPoint(x: 104.7, y: 47.6), to: CGPoint(x: 145, y: 49), sag: 2,
      colour: rope, width: 0.35)
  }

  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far:
      sunAndGlitter(context, moment: moment)
      sailboat(context, moment: moment)
    case .middle:
      lighthouseBeam(context, moment: moment)
      for lamp in Self.pierLamps {
        ViewKit.circle(
          context, lamp, 0.45,
          moment.lamps > 0.5 ? ViewPalette.lampCore : moment.palette.middle.lit(0.1))
        ViewKit.glow(context, lamp, 4, ViewPalette.lamp, 0.5 * moment.lamps)
        ViewKit.rect(
          context, CGRect(x: lamp.x - 0.6, y: Self.horizon + 7, width: 1.2, height: 4),
          ViewPalette.lamp, 0.25 * moment.lamps)
      }
      gulls(context, moment: moment)
    case .street:
      waves(context, moment: moment)
      ViewKit.litWindow(context, Self.shackWindow, level: moment.lamps)
      ViewLightString(
        from: CGPoint(x: Self.shack.maxX + 1.6, y: Self.shack.minY + 0.4),
        to: CGPoint(x: Self.tower.minX - 0.6, y: Self.tower.minY - 0.4), sag: 1.8, count: 14,
        colours: [ViewColour(0xFFD166), ViewColour(0xFF8A5B), ViewColour(0x7AE0C0)], seed: 3
      ).draw(context, moment: moment)
      flag(context, moment: moment)
      Self.walker.draw(context, moment: moment)
    case .near:
      dunegrass(context, moment: moment)
    }
  }

  /// The breeze, from about -1 to 1, never quite repeating.
  static func breeze(_ moment: ViewMoment) -> Double {
    let t = moment.now
    let wind = moment.look.weather == .rain ? 1.8 : 1
    return (0.55 * sin(t * 0.6) + 0.3 * sin(t * 1.7 + 1) + 0.15 * sin(t * 3.7)) * wind
  }

  /// The low sun and its glitter path on the water at sunset and sunrise; the moon's at night.
  private func sunAndGlitter(_ context: GraphicsContext, moment: ViewMoment) {
    let look = moment.look
    guard look.weather != .rain, look.weather != .snow else { return }
    let alpha = look.weather == .fog ? 0.35 : 1.0
    let source: CGPoint
    let colour: ViewColour
    switch look.hour {
    case .dusk, .morning:
      source = Self.sun
      colour = ViewColour(0xFFB86A)
    case .night:
      source = CGPoint(x: moon.x, y: Self.horizon)
      colour = ViewColour(0xDDE6FF)
    case .day: return
    }
    if look.hour != .night {
      ViewKit.glow(context, Self.sun, 24, colour, 0.35 * alpha)
      var sky = context
      sky.clip(to: Path(CGRect(x: -45, y: -50, width: 190, height: Self.horizon + 50)))
      ViewKit.circle(sky, Self.sun, 5, ViewColour(0xFFD9A0), 0.95 * alpha)
    }
    for index in 0..<18 {
      let share = CGFloat(index) / 17
      let y = Self.horizon + 0.6 + share * share * 13
      let spread = 1.5 + share * 9
      let jitter = CGFloat(ViewRhythm.hash(index, seed: 831)) - 0.5
      let x =
        source.x + jitter * 2 * spread + CGFloat(sin(moment.now * 0.8 + Double(index) * 1.7)) * 0.8
      let speed = 1.5 + 2 * ViewRhythm.hash(index, seed: 832)
      let shimmer = 0.5 + 0.5 * sin(moment.now * speed + Double(index))
      let width = 1.2 + share * 3.5
      ViewKit.rect(
        context, CGRect(x: x - width / 2, y: y, width: width, height: 0.22 + share * 0.2), colour,
        0.75 * shimmer * alpha)
    }
  }

  static func boatPoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    let p = CGFloat(pass.progress)
    let x = pass.variant < 0.5 ? -15 + 130 * p : 115 - 130 * p
    return CGPoint(x: x, y: horizon + 1.4)
  }

  /// A small sailboat sliding along the horizon, its mast light on after dark.
  private func sailboat(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = Self.boat.pass(at: moment.now) else { return }
    let point = Self.boatPoint(pass)
    let facing: CGFloat = pass.variant < 0.5 ? 1 : -1
    let bob = CGFloat(sin(moment.now * 1.4)) * 0.15
    let hullColour = moment.palette.far.lit(-0.4)
    var hull = Path()
    hull.move(to: CGPoint(x: point.x - 2.4 * facing, y: point.y - 0.8 + bob))
    hull.addLine(to: CGPoint(x: point.x + 2.6 * facing, y: point.y - 0.8 + bob))
    hull.addLine(to: CGPoint(x: point.x + 1.8 * facing, y: point.y + bob))
    hull.addLine(to: CGPoint(x: point.x - 1.8 * facing, y: point.y + bob))
    hull.closeSubpath()
    context.fill(hull, with: .color(hullColour.color()))
    let sail = ViewColour(0xF4E6D8).mixed(
      with: moment.palette.far, by: moment.look.isDark ? 0.55 : 0.2)
    var main = Path()
    main.move(to: CGPoint(x: point.x - 0.1 * facing, y: point.y - 1.1 + bob))
    main.addLine(to: CGPoint(x: point.x - 0.1 * facing, y: point.y - 6.4 + bob))
    main.addLine(to: CGPoint(x: point.x - 2.3 * facing, y: point.y - 1.1 + bob))
    main.closeSubpath()
    context.fill(main, with: .color(sail.color()))
    var jib = Path()
    jib.move(to: CGPoint(x: point.x + 0.2 * facing, y: point.y - 1.1 + bob))
    jib.addLine(to: CGPoint(x: point.x + 0.2 * facing, y: point.y - 5.4 + bob))
    jib.addLine(to: CGPoint(x: point.x + 2.2 * facing, y: point.y - 1.1 + bob))
    jib.closeSubpath()
    context.fill(jib, with: .color(sail.lit(-0.08).color()))
    if moment.look.isDark {
      let top = CGPoint(x: point.x - 0.1 * facing, y: point.y - 6.6 + bob)
      ViewKit.circle(context, top, 0.2, ViewPalette.lampCore)
      ViewKit.glow(context, top, 1.4, ViewPalette.lampCore, 0.5)
    }
  }

  /// The lighthouse's beam sweeping round after dark, brightest as it turns towards the window.
  private func lighthouseBeam(_ context: GraphicsContext, moment: ViewMoment) {
    let lamp = Self.lighthouse
    let level = moment.lamps
    ViewKit.rect(
      context, CGRect(x: lamp.x - 0.7, y: lamp.y - 0.6, width: 1.4, height: 1.4),
      level > 0.5 ? ViewPalette.lampCore : moment.palette.middle.lit(0.15))
    guard level > 0 else { return }
    let angle = moment.now * 0.9
    let reach = CGFloat(sin(angle)) * 70
    let facing = cos(angle)
    let thick = moment.look.weather == .clear ? 1.0 : 1.5
    var beam = Path()
    beam.move(to: CGPoint(x: lamp.x, y: lamp.y - 0.4))
    beam.addLine(to: CGPoint(x: lamp.x + reach, y: lamp.y - 3.4))
    beam.addLine(to: CGPoint(x: lamp.x + reach, y: lamp.y + 3))
    beam.addLine(to: CGPoint(x: lamp.x, y: lamp.y + 0.4))
    beam.closeSubpath()
    context.fill(
      beam,
      with: .linearGradient(
        Gradient(colors: [
          ViewPalette.lampCore.color(0.35 * level * thick * abs(sin(angle))),
          ViewPalette.lampCore.color(0),
        ]), startPoint: lamp, endPoint: CGPoint(x: lamp.x + reach, y: lamp.y)))
    let flash = max(0, facing - 0.8) / 0.2
    ViewKit.glow(
      context, lamp, 3 + 6 * CGFloat(flash), ViewPalette.lampCore, (0.4 + 0.5 * flash) * level)
  }

  static func gullPoint(_ pass: ViewRhythm.Pass, bird: Int, now: Double) -> CGPoint {
    let p = CGFloat(pass.progress)
    let lag = CGFloat(bird) * 0.06
    let share = max(0, p - lag) * 1.2
    let x = pass.variant < 0.5 ? -15 + 135 * share : 115 - 135 * share
    let y =
      6 + 8 * CGFloat(pass.variant) + CGFloat(bird) * 2.2
      + CGFloat(sin(now * 0.7 + Double(bird) * 2)) * 1.4
    return CGPoint(x: x, y: y)
  }

  /// Three gulls gliding over in a loose line while it is light, now and then a wingbeat.
  private func gulls(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.hour != .night, moment.look.weather != .snow,
      let pass = Self.gulls.pass(at: moment.now)
    else { return }
    let colour = ViewColour(0xF4F1EA).mixed(
      with: moment.palette.middle, by: moment.look.isDark ? 0.5 : 0.15)
    for bird in 0..<3 {
      let point = Self.gullPoint(pass, bird: bird, now: moment.now)
      let beat = sin(moment.now * 5 + Double(bird) * 2)
      let lift = CGFloat(beat > 0.6 ? (beat - 0.6) * 2 : 0) + 0.25
      var wings = Path()
      wings.move(to: CGPoint(x: point.x - 1.6, y: point.y - lift))
      wings.addQuadCurve(to: point, control: CGPoint(x: point.x - 0.8, y: point.y - lift - 0.6))
      wings.addQuadCurve(
        to: CGPoint(x: point.x + 1.6, y: point.y - lift),
        control: CGPoint(x: point.x + 0.8, y: point.y - lift - 0.6))
      context.stroke(wings, with: .color(colour.color()), lineWidth: 0.3)
    }
  }

  /// Waves running up the sand one after another, their foam sliding up and slipping back.
  private func waves(_ context: GraphicsContext, moment: ViewMoment) {
    let palette = moment.palette
    let dark = moment.look.isDark
    let foam = ViewColour(0xFFF6EC).mixed(with: palette.far, by: dark ? 0.55 : 0.15)
    let water = palette.far.lit(dark ? 0.04 : 0.1)
    let period = moment.look.weather == .rain ? 5.5 : 7.5
    let base = Self.shore
    // A breaker further out, rising and settling.
    let swell = 0.5 + 0.5 * sin(moment.now * 2 * .pi / period)
    var breaker = Path()
    breaker.move(to: CGPoint(x: -45, y: 38.6))
    var x: CGFloat = -45
    while x < 145 {
      let wobble = CGFloat(sin(Double(x) * 0.21 + moment.now * 0.5)) * 0.3
      breaker.addQuadCurve(
        to: CGPoint(x: x + 12, y: 38.6 + wobble), control: CGPoint(x: x + 6, y: 38.2 - wobble))
      x += 12
    }
    context.stroke(breaker, with: .color(foam.color(0.25 + 0.3 * swell)), lineWidth: 0.35)
    for wave in 0..<3 {
      let cycle = moment.now / period + Double(wave) / 3
      let phase = cycle - cycle.rounded(.down)
      let reach = sin(phase * .pi)
      let y = 40.6 + CGFloat(reach) * 6.2 + CGFloat(wave) * 0.3
      let alpha = phase < 0.5 ? 0.85 : 0.85 * (1 - (phase - 0.5) * 2)
      if y > base {
        context.fill(
          Path(CGRect(x: -45, y: base, width: 190, height: y - base)),
          with: .color(water.color(0.3 * alpha)))
      }
      var line = Path()
      line.move(to: CGPoint(x: -45, y: y))
      var segment: CGFloat = -45
      while segment < 145 {
        let wobble = CGFloat(sin(Double(segment) * 0.13 + moment.now * 0.6 + Double(wave) * 2))
        line.addQuadCurve(
          to: CGPoint(x: segment + 10, y: y + wobble * 0.5),
          control: CGPoint(x: segment + 5, y: y - 0.5 + wobble * 0.3))
        segment += 10
      }
      context.stroke(line, with: .color(foam.color(alpha)), lineWidth: 0.45)
    }
  }

  /// The lifeguard tower's flag lifting in the breeze.
  private func flag(_ context: GraphicsContext, moment: ViewMoment) {
    let top = Self.flag
    let flutter = CGFloat(sin(moment.now * 6)) * 0.4
    let lift = CGFloat(Self.breeze(moment)) * 0.4
    var cloth = Path()
    cloth.move(to: top)
    cloth.addQuadCurve(
      to: CGPoint(x: top.x + 3.2, y: top.y + 0.8 - lift),
      control: CGPoint(x: top.x + 1.6, y: top.y + flutter))
    cloth.addLine(to: CGPoint(x: top.x + 3.2, y: top.y + 2.2 - lift))
    cloth.addQuadCurve(
      to: CGPoint(x: top.x, y: top.y + 1.8),
      control: CGPoint(x: top.x + 1.6, y: top.y + 2 + flutter))
    cloth.closeSubpath()
    context.fill(
      cloth,
      with: .color(
        ViewColour(0xE5503A).mixed(with: moment.palette.street, by: moment.look.isDark ? 0.5 : 0.15)
          .color()))
  }

  /// Dune grass in tufts, bending with the breeze.
  private func dunegrass(_ context: GraphicsContext, moment: ViewMoment) {
    let sway = Self.breeze(moment)
    let colour = moment.palette.near.mixed(
      with: ViewColour(0x9AA86A), by: moment.look.isDark ? 0.12 : 0.35)
    let tufts: [(x: CGFloat, y: CGFloat)] = [
      (-10, 55.4), (-2, 54.2), (8, 54.4), (18, 55.8), (78, 58.6), (96, 58.4), (112, 58),
    ]
    for (index, tuft) in tufts.enumerated() {
      var blades = Path()
      for blade in 0..<6 {
        let spread = (CGFloat(blade) - 2.5) * 0.9
        let height = 5 + 3 * CGFloat(ViewRhythm.hash(index * 7 + blade, seed: 861))
        let bend =
          CGFloat(sway) * height * 0.22 + spread * 0.8
          + CGFloat(sin(moment.now * 1.3 + Double(index + blade))) * 0.3
        let root = CGPoint(x: tuft.x + spread * 0.4, y: tuft.y)
        blades.move(to: root)
        blades.addQuadCurve(
          to: CGPoint(x: root.x + bend, y: root.y - height),
          control: CGPoint(x: root.x + bend * 0.2, y: root.y - height * 0.6))
      }
      context.stroke(
        blades, with: .color(colour.lit(index % 2 == 0 ? 0 : 0.05).color()), lineWidth: 0.4)
    }
  }

  func headlight(at now: Double) -> ViewHeadlight? { nil }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if moment.look.hour != .night, moment.look.weather != .snow,
      let pass = Self.gulls.pass(at: moment.now)
    {
      let lead = Self.gullPoint(pass, bird: 0, now: moment.now)
      if lead.x > 0, lead.x < 100 {
        return ViewInterest(point: lead, plane: .middle, paw: false, id: pass.index)
      }
    }
    if let walker = Self.walker.interest(at: moment.now) { return walker }
    if let pass = Self.boat.pass(at: moment.now) {
      let point = Self.boatPoint(pass)
      if point.x > 2, point.x < 98 {
        return ViewInterest(
          point: CGPoint(x: point.x, y: point.y - 3), plane: .far, paw: false, id: pass.index)
      }
    }
    return nil
  }
}
