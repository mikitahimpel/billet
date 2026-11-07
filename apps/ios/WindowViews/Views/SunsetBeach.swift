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
}
