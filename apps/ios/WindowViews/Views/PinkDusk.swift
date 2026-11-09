import CoreGraphics
import Foundation
import Pet
import SwiftUI

struct PinkDusk: ViewRecipe {
  static let streetBase: CGFloat = 46
  static let roadway = ViewRoad(
    line: 51, kerb: streetBase, cars: ViewRhythm(seed: 701, slot: 18, chance: 0.7, length: 4...6),
    length: 12, bodies: [0xE8E4DC, 0x2A2A30, 0xC85A6A, 0x6AA8B8, 0x3A3A40])
  static let lamp = ViewStreetLamp(head: CGPoint(x: 60, y: 16), ground: streetBase)
  static let palms: [(x: CGFloat, height: CGFloat, lean: CGFloat)] = [
    (-26, 36, 2), (-4, 40, -1.5), (16, 34, 1.2), (40, 42, 2.4), (62, 37, -2), (86, 41, 1),
    (110, 35, -1.2),
  ]
  static let palmBase: CGFloat = 41
  static let truck = CGRect(x: 18, y: 38.4, width: 17, height: 8.6)
  static let skater = ViewWalker(
    rhythm: ViewRhythm(seed: 711, slot: 40, chance: 0.6, length: 6...9),
    from: CGPoint(x: -20, y: 47.4), to: CGPoint(x: 120, y: 47.4), height: 6.2,
    kinds: [.skater, .skater, .walker, .phone], coats: [0xF2F0EA, 0xFF8A5B, 0x3A3A40, 0x9AC8E8])
  static let parrots = ViewRhythm(seed: 721, slot: 60, chance: 0.55, length: 7...10)
  /// Seconds between planes on the approach; most slots have one.
  static let approachGap: Double = 26

  var moon: CGPoint { CGPoint(x: 22, y: -10) }
  var livePlanes: Set<ViewPlane> { [.far, .middle, .street, .near] }

  func paint(_ plane: ViewPlane, _ context: GraphicsContext, look: ViewLook) {
    let colour = look.palette.colour(plane)
    switch plane {
    case .far: paintFar(context, colour: colour, look: look)
    case .middle: paintMiddle(context, colour: colour, look: look)
    case .street: paintStreet(context, colour: colour, look: look)
    case .near: paintNear(context, colour: colour, look: look)
    }
  }

  // MARK: - Far: hills, downtown and ridge palms

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    for (index, tower) in [(64.0, 4.0, 20.0), (69, 5, 15), (75, 3.4, 22), (79, 5, 18), (85, 4, 24)]
      .enumerated() as EnumeratedSequence<[(CGFloat, CGFloat, CGFloat)]>
    {
      ViewKit.rect(
        context, CGRect(x: tower.0, y: tower.2, width: tower.1, height: 36 - tower.2),
        colour.mixed(with: look.palette.horizon, by: 0.3).lit(Double(index % 2) * 0.03))
    }
    ViewKit.hills(context, base: 34, waves: [3, 5, 2.4, 4, 6, 3, 2, 4.4, 3.6], colour: colour)
    if look.isDark {
      for index in 0..<70 {
        let x = -40 + 180 * CGFloat(ViewRhythm.hash(index, seed: 741))
        let y = 30 + 7 * CGFloat(ViewRhythm.hash(index, seed: 742))
        ViewKit.circle(
          context, CGPoint(x: x, y: y), 0.25, ViewPalette.lamp,
          0.4 + 0.4 * ViewRhythm.hash(index, seed: 743))
      }
    }
    for index in 0..<12 {
      let x = -36 + CGFloat(index) * 15 + 6 * CGFloat(ViewRhythm.hash(index, seed: 744))
      ViewKit.palm(
        context, x: x, base: 34, height: 9 + 5 * CGFloat(ViewRhythm.hash(index, seed: 745)),
        lean: CGFloat(ViewRhythm.hash(index, seed: 746) - 0.5) * 2, colour: colour.lit(-0.04))
    }
    ViewKit.ground(context, top: 36, colour: colour.lit(-0.02))
  }

  // MARK: - Middle: stucco and the donut

  static let donut = CGPoint(x: 80, y: 29)

  static let middleWindows: [ViewLitWindow] = {
    var windows: [ViewLitWindow] = []
    for floor in 0..<2 {
      for column in 0..<5 {
        let rect = CGRect(
          x: -16 + CGFloat(column) * 8, y: 29 + CGFloat(floor) * 5, width: 4.6, height: 2.6)
        windows.append(
          ViewLitWindow(
            id: 900 + floor * 5 + column, rect: rect, plane: .middle,
            isTV: (floor + column) % 4 == 2))
      }
    }
    return windows
  }()

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let stucco = colour.mixed(with: ViewColour(0xE8C8B8), by: look.isDark ? 0.12 : 0.3)
    let block = CGRect(x: -20, y: 26, width: 42, height: 15)
    ViewKit.rect(context, block, stucco)
    ViewKit.rect(
      context,
      CGRect(x: block.minX - 0.6, y: block.minY - 0.8, width: block.width + 1.2, height: 0.8),
      stucco.lit(0.08))
    for window in Self.middleWindows { ViewKit.windowFrame(context, window.rect, stucco) }
    ViewKit.rect(
      context, CGRect(x: block.minX, y: block.maxY - 3, width: block.width, height: 3),
      stucco.lit(-0.25))
    for x in stride(from: block.minX + 4, to: block.maxX, by: 8) {
      ViewKit.rect(context, CGRect(x: x, y: block.maxY - 3, width: 0.6, height: 3), stucco)
    }
    let bungalow = CGRect(x: 30, y: 34, width: 22, height: 7)
    ViewKit.rect(context, bungalow, stucco.lit(-0.04))
    var roof = Path()
    roof.move(to: CGPoint(x: bungalow.minX - 1.4, y: bungalow.minY))
    roof.addLine(to: CGPoint(x: bungalow.minX + 4, y: bungalow.minY - 3))
    roof.addLine(to: CGPoint(x: bungalow.maxX - 4, y: bungalow.minY - 3))
    roof.addLine(to: CGPoint(x: bungalow.maxX + 1.4, y: bungalow.minY))
    roof.closeSubpath()
    context.fill(
      roof, with: .color(stucco.mixed(with: ViewColour(0xA85A40), by: 0.25).lit(-0.08).color()))
    let shop = CGRect(x: 68, y: 35, width: 26, height: 6)
    ViewKit.rect(context, shop, stucco.lit(0.03))
    ViewKit.rect(
      context, CGRect(x: shop.minX + 1.6, y: shop.minY + 1.4, width: shop.width - 3.2, height: 3.2),
      stucco.lit(-0.2))
    let donut = Self.donut
    for dx in [-1.6, 1.6] as [CGFloat] {
      ViewKit.rect(
        context,
        CGRect(x: donut.x + dx - 0.25, y: donut.y + 3, width: 0.5, height: shop.minY - donut.y - 3),
        stucco.lit(-0.15))
    }
    let dough = ViewColour(0xD89A5A).mixed(with: colour, by: look.isDark ? 0.55 : 0.25)
    context.stroke(
      Path(ellipseIn: CGRect(x: donut.x - 3.6, y: donut.y - 3.6, width: 7.2, height: 7.2)),
      with: .color(dough.color()), lineWidth: 2.6)
    ViewKit.ground(context, top: Self.palmBase, colour: colour.lit(-0.04))
  }

  // MARK: - Street: the boulevard

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let base = Self.streetBase
    let wall = CGRect(x: 76, y: 39.4, width: 70, height: base - 39.4)
    ViewKit.rect(
      context, wall, colour.mixed(with: ViewColour(0xE8C8B8), by: look.isDark ? 0.1 : 0.25))
    let bloom = ViewColour(0xE0408A).mixed(with: colour, by: look.isDark ? 0.55 : 0.2)
    let leaves = colour.mixed(with: ViewColour(0x3F7A4E), by: look.isDark ? 0.15 : 0.4)
    for index in 0..<30 {
      let x = wall.minX + CGFloat(index) * 2.4 + CGFloat(ViewRhythm.hash(index, seed: 751)) * 1.6
      let y = wall.minY + 1 + CGFloat(ViewRhythm.hash(index, seed: 752)) * 3.4
      ViewKit.circle(context, CGPoint(x: x, y: y), 1.6, index % 3 == 0 ? leaves : bloom)
      if index % 4 == 1 {
        ViewKit.circle(context, CGPoint(x: x + 0.6, y: y + 2.6), 1, bloom.lit(-0.05))
      }
    }
    let truck = Self.truck
    let paint = ViewColour(0xF2EEE6).mixed(with: colour, by: look.isDark ? 0.6 : 0.25)
    ViewKit.rect(
      context,
      CGRect(x: truck.minX, y: truck.minY, width: truck.width - 4, height: truck.height - 1.6),
      paint)
    ViewKit.rect(
      context,
      CGRect(x: truck.maxX - 4.4, y: truck.minY + 2.6, width: 4.4, height: truck.height - 4.2),
      paint.lit(-0.04))
    ViewKit.rect(
      context, CGRect(x: truck.maxX - 3.6, y: truck.minY + 3.2, width: 2.6, height: 1.8),
      colour.lit(-0.2))
    ViewKit.rect(
      context, CGRect(x: truck.minX + 2, y: truck.minY + 2, width: 8.4, height: 3), colour.lit(-0.3)
    )
    var hatch = Path()
    hatch.move(to: CGPoint(x: truck.minX + 1.6, y: truck.minY + 2))
    hatch.addLine(to: CGPoint(x: truck.minX + 10.8, y: truck.minY + 2))
    hatch.addLine(to: CGPoint(x: truck.minX + 11.6, y: truck.minY - 0.6))
    hatch.addLine(to: CGPoint(x: truck.minX + 0.8, y: truck.minY - 0.6))
    hatch.closeSubpath()
    context.fill(hatch, with: .color(paint.lit(0.04).color()))
    ViewKit.rect(
      context, CGRect(x: truck.minX, y: truck.maxY - 3.4, width: truck.width - 4, height: 0.6),
      ViewColour(0xE5503A).mixed(with: colour, by: look.isDark ? 0.5 : 0.2))
    for x in [truck.minX + 3, truck.maxX - 3.4] {
      ViewKit.circle(context, CGPoint(x: x, y: truck.maxY - 1.2), 1.2, colour.lit(-0.4))
    }
    for (index, x) in [12.0, 15.4].enumerated() {
      ViewWalker.figure(
        context, at: CGPoint(x: x, y: base), height: 6, facing: 1,
        kind: index == 0 ? .phone : .walker,
        coat: index == 0 ? 0x9AC8E8 : 0xFF8A5B, plane: .street,
        moment: ViewMoment(look: look, now: 0, time: 10), walking: false)
    }
    ViewKit.rect(
      context, CGRect(x: -45, y: base, width: 190, height: 1.2),
      colour.lit(look.isDark ? 0.06 : 0.15))
    ViewKit.ground(context, top: base + 1.2, colour: colour.lit(-0.2))
    ViewKit.streetLampPost(
      context, x: Self.lamp.head.x + 5, top: Self.lamp.head.y - 0.6, base: base + 1.2,
      colour: colour.lit(-0.25))
  }

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let agave = colour.mixed(with: ViewColour(0x5A8A7A), by: look.isDark ? 0.15 : 0.35)
    for index in 0..<9 {
      let angle = -Double.pi * (0.1 + 0.8 * Double(index) / 8)
      let length: CGFloat = 9 + CGFloat(index % 3) * 2
      let root = CGPoint(x: 6, y: 60)
      let tip = CGPoint(
        x: root.x + CGFloat(cos(angle)) * length * 1.2, y: root.y + CGFloat(sin(angle)) * length)
      var leaf = Path()
      leaf.move(to: CGPoint(x: root.x - 1.4, y: root.y))
      leaf.addQuadCurve(
        to: tip, control: CGPoint(x: (root.x + tip.x) / 2 - 1, y: (root.y + tip.y) / 2))
      leaf.addQuadCurve(
        to: CGPoint(x: root.x + 1.4, y: root.y),
        control: CGPoint(x: (root.x + tip.x) / 2 + 1, y: (root.y + tip.y) / 2))
      leaf.closeSubpath()
      context.fill(leaf, with: .color(agave.lit(index % 2 == 0 ? 0.04 : -0.02).color()))
    }
    ViewKit.ground(context, top: 58, colour: colour)
  }

  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: approach(context, moment: moment)
    case .middle:
      ViewWindows.draw(Self.middleWindows, context, moment: moment)
      donutGlow(context, moment: moment)
      let sway = Self.sway(moment)
      let colour = moment.palette.middle.lit(-0.08)
      for (index, palm) in Self.palms.enumerated() {
        ViewKit.palm(
          context, x: palm.x, base: Self.palmBase, height: palm.height, lean: palm.lean,
          colour: colour.lit(index % 2 == 0 ? 0 : -0.03),
          sway: sway + 0.2 * sin(moment.now * 0.9 + Double(index)))
      }
      parrots(context, moment: moment)
    case .street:
      truckLights(context, moment: moment)
      hummingbird(context, moment: moment)
      Self.lamp.draw(context, moment: moment)
      Self.skater.draw(context, moment: moment)
      Self.roadway.draw(context, moment: moment)
    case .near:
      let sway = Self.sway(moment)
      for (index, angle) in [0.3, 0.55, 0.85, 1.1].enumerated() {
        ViewKit.palmFrond(
          context, from: CGPoint(x: 112, y: -14), angle: Double.pi - angle + sway * 0.08,
          length: 30 - CGFloat(index) * 3, colour: moment.palette.near.lit(Double(index % 2) * 0.04)
        )
      }
    }
  }

  static let hummer = ViewRhythm(seed: 761, slot: 45, chance: 0.6, length: 16...24)

  static func hummerPoint(_ pass: ViewRhythm.Pass, now: Double) -> CGPoint {
    let flowers = [
      CGPoint(x: 80, y: 40.6), CGPoint(x: 86, y: 42.4), CGPoint(x: 92, y: 40.2),
      CGPoint(x: 98, y: 41.8),
    ]
    let stops = Double(flowers.count)
    let step = pass.progress * stops
    let index = min(Int(step), flowers.count - 1)
    let next = flowers[(index + 1) % flowers.count]
    let here = flowers[index]
    let local = step - Double(index)
    let dart = CGFloat(max(0, (local - 0.8) / 0.2))
    let x = here.x + (next.x - here.x) * dart + CGFloat(sin(now * 9)) * 0.15
    let y = here.y - 1.2 + (next.y - here.y) * dart + CGFloat(sin(now * 13)) * 0.2
    return CGPoint(x: x, y: y)
  }

  private func hummingbird(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.hour != .night, moment.look.weather == .clear,
      let pass = Self.hummer.pass(at: moment.now)
    else { return }
    let point = Self.hummerPoint(pass, now: moment.now)
    let body = ViewColour(0x3DBF8A).mixed(
      with: moment.palette.street, by: moment.look.isDark ? 0.5 : 0.2)
    context.fill(
      Path(ellipseIn: CGRect(x: point.x - 0.7, y: point.y - 0.3, width: 1.4, height: 0.6)),
      with: .color(body.color()))
    ViewKit.circle(context, CGPoint(x: point.x - 0.7, y: point.y - 0.2), 0.3, body.lit(0.05))
    var beak = Path()
    beak.move(to: CGPoint(x: point.x - 0.95, y: point.y - 0.2))
    beak.addLine(to: CGPoint(x: point.x - 1.9, y: point.y))
    context.stroke(beak, with: .color(body.lit(-0.4).color()), lineWidth: 0.1)
    context.fill(
      Path(ellipseIn: CGRect(x: point.x - 0.4, y: point.y - 1.3, width: 1.2, height: 1.1)),
      with: .color(ViewColour(0xEEF2F7).color(0.35)))
  }

  /// From -1 to 1, never quite repeating.
  static func sway(_ moment: ViewMoment) -> Double {
    let t = moment.now
    let wind = moment.look.weather == .rain ? 1.8 : 1
    return (0.55 * sin(t * 0.45) + 0.3 * sin(t * 1.3 + 2) + 0.15 * sin(t * 3.1)) * wind
  }

  private func approach(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.weather != .fog else { return }
    let slot = Self.approachGap
    let base = (moment.now / slot).rounded(.down)
    for offset in 0..<5 {
      let index = base - Double(offset)
      let p = (moment.now - index * slot) / (slot * 5)
      guard p >= 0, p < 1,
        ViewRhythm.hash(Int(index.truncatingRemainder(dividingBy: 1_000_000)), seed: 732) < 0.85
      else { continue }
      let x = -30 + 150 * CGFloat(p)
      let y = 2 + 22 * CGFloat(p)
      let light = ViewPalette.lampCore
      let bright = moment.look.isDark ? 1.0 : 0.6
      ViewKit.circle(context, CGPoint(x: x, y: y), 0.35, light, bright)
      ViewKit.glow(context, CGPoint(x: x, y: y), 2.4, light, 0.45 * bright)
      if sin(moment.now * 6 + Double(offset)) > 0.7 {
        ViewKit.circle(context, CGPoint(x: x - 0.8, y: y - 0.2), 0.2, ViewColour(0xFF3B3B), bright)
      }
    }
  }

  private func donutGlow(_ context: GraphicsContext, moment: ViewMoment) {
    let donut = Self.donut
    let neon = ViewColour(0xFF6FA8)
    let level = moment.lamps
    guard level > 0 else { return }
    context.stroke(
      Path(ellipseIn: CGRect(x: donut.x - 3.6, y: donut.y - 3.6, width: 7.2, height: 7.2)),
      with: .color(neon.color(0.85 * level)), lineWidth: 1.4)
    ViewKit.glow(context, donut, 9, neon, 0.3 * level)
  }

  private func truckLights(_ context: GraphicsContext, moment: ViewMoment) {
    let truck = Self.truck
    let level = moment.look.isDark ? 1.0 : 0.3
    ViewKit.rect(
      context, CGRect(x: truck.minX + 2, y: truck.minY + 2, width: 8.4, height: 3),
      ViewColour(0xFFF2D8), 0.75 * level)
    ViewKit.glow(
      context, CGPoint(x: truck.minX + 6, y: truck.minY + 4), 9, ViewPalette.lamp, 0.35 * level)
    ViewLightString(
      from: CGPoint(x: truck.minX + 0.8, y: truck.minY - 0.6), to: CGPoint(x: -8, y: 34),
      sag: 1.2, count: 9,
      colours: [ViewColour(0xFF8A5B), ViewColour(0xFFD166), ViewColour(0x7AE0C0)],
      seed: 7
    ).draw(context, moment: moment)
  }

  private func parrots(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.hour != .night, moment.look.weather == .clear,
      let pass = Self.parrots.pass(at: moment.now)
    else { return }
    let green = ViewColour(0x4ACB5A).mixed(
      with: moment.palette.middle, by: moment.look.isDark ? 0.55 : 0.2)
    for bird in 0..<8 {
      let point = Self.parrotPoint(pass, bird: bird, now: moment.now)
      let flap = CGFloat(sin(moment.now * 22 + Double(bird) * 1.3))
      var wings = Path()
      wings.move(to: CGPoint(x: point.x - 1.2, y: point.y - flap * 0.9))
      wings.addLine(to: point)
      wings.addLine(to: CGPoint(x: point.x + 1.2, y: point.y - flap * 0.9))
      context.stroke(wings, with: .color(green.color()), lineWidth: 0.45)
      ViewKit.circle(context, point, 0.4, green.lit(0.05))
    }
  }

  static func parrotPoint(_ pass: ViewRhythm.Pass, bird: Int, now: Double) -> CGPoint {
    let p = CGFloat(pass.progress)
    let lag = CGFloat(bird) * 0.035
    let share = max(0, p - lag) * 1.3
    let x = pass.variant < 0.5 ? -20 + 150 * share : 120 - 150 * share
    let y =
      10 + 6 * CGFloat(pass.variant) + CGFloat(bird % 3) * 1.4
      + CGFloat(sin(now * 2 + Double(bird))) * 0.8
    return CGPoint(x: x, y: y)
  }

  func headlight(at now: Double) -> ViewHeadlight? { Self.roadway.headlight(at: now) }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if moment.look.hour != .night, moment.look.weather == .clear,
      let pass = Self.parrots.pass(at: moment.now)
    {
      let lead = Self.parrotPoint(pass, bird: 0, now: moment.now)
      if lead.x > 0, lead.x < 100 {
        return ViewInterest(point: lead, plane: .middle, paw: false, id: pass.index)
      }
    }
    if moment.look.hour != .night, moment.look.weather == .clear,
      let pass = Self.hummer.pass(at: moment.now)
    {
      return ViewInterest(
        point: Self.hummerPoint(pass, now: moment.now), plane: .street, paw: false,
        id: pass.index)
    }
    return Self.skater.interest(at: moment.now) ?? Self.roadway.interest(at: moment.now)
  }
}
