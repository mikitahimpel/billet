import CoreGraphics
import Foundation
import Pet
import SwiftUI

struct RainySuburb: ViewRecipe {
  static let streetBase: CGFloat = 48
  static let lampHead = CGPoint(x: 8, y: 13)
  static let roadway = ViewRoad(
    line: 53.4, kerb: streetBase,
    cars: ViewRhythm(seed: 221, slot: 18, chance: 0.7, length: 3.8...5.6))
  static let lamp = ViewStreetLamp(head: lampHead, ground: streetBase, shines: [74, 90])
  static let walker = ViewRhythm(seed: 231, slot: 55, chance: 0.55, length: 20...28)
  static let lightning = ViewRhythm(seed: 241, slot: 75, chance: 0.4, length: 0.7...1.1)
  static let highway: CGFloat = 30.5
  static let porch = CGPoint(x: 3, y: 41)

  var moon: CGPoint { CGPoint(x: 20, y: -16) }
  var livePlanes: Set<ViewPlane> { [.far, .middle, .street, .near] }

  // MARK: - Still planes

  func paint(_ plane: ViewPlane, _ context: GraphicsContext, look: ViewLook) {
    let colour = look.palette.colour(plane)
    switch plane {
    case .far: paintFar(context, colour: colour, look: look)
    case .middle: paintMiddle(context, colour: colour, look: look)
    case .street: paintStreet(context, colour: colour, look: look)
    case .near: paintNear(context, colour: colour, look: look)
    }
  }

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    ViewKit.hills(context, base: 34, waves: [4, 6, 3, 5, 7, 3, 4, 5], colour: colour.lit(0.04))
    ViewKit.ground(context, top: 34, colour: colour)
    ViewKit.rect(context, CGRect(x: -45, y: Self.highway, width: 190, height: 1), colour.lit(-0.12))
    var x: CGFloat = -40
    while x < 145 {
      ViewKit.rect(
        context, CGRect(x: x, y: Self.highway + 1, width: 0.7, height: 4), colour.lit(-0.12))
      x += 11
    }
    ViewKit.rect(context, CGRect(x: 88, y: 12, width: 0.8, height: 22), colour.lit(-0.1))
    for y in [13.0, 15.5] as [CGFloat] {
      ViewKit.rect(context, CGRect(x: 86.4, y: y, width: 4, height: 1.2), colour.lit(-0.1))
    }
  }

  static let middleHouses: [(x: CGFloat, width: CGFloat, wall: CGFloat, roof: CGFloat)] = [
    (-34, 24, 6, 3.6), (-6, 22, 6.5, 3.2), (20, 26, 5.8, 3.8), (50, 22, 6.4, 3.4),
    (76, 26, 6, 3.6), (106, 24, 6.6, 3.4), (132, 20, 6, 3.2),
  ]
  static let middleBase: CGFloat = 40

  static let middleWindows: [ViewLitWindow] = middleHouses.enumerated().flatMap { index, house in
    [0.18, 0.5, 0.78].enumerated().map { slot, share in
      ViewLitWindow(
        id: 300 + index * 3 + slot,
        rect: CGRect(
          x: house.x + house.width * share, y: middleBase - house.wall + 1.6, width: 2.6,
          height: 2), plane: .middle)
    }
  }

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    for (index, tree) in [(-12.0, 9.0), (16, 8), (46, 10), (73, 8.5), (102, 9)].enumerated() {
      ViewKit.tree(
        context, x: tree.0, base: Self.middleBase, size: tree.1, colour: colour.lit(-0.04),
        seed: 20 + index, look: look)
    }
    for (index, house) in Self.middleHouses.enumerated() {
      ViewKit.house(
        context, x: house.x, base: Self.middleBase, width: house.width, wall: house.wall,
        roof: house.roof, colour: colour.lit(index % 2 == 0 ? 0.03 : -0.02), look: look,
        overhang: 1.6)
    }
    for window in Self.middleWindows { ViewKit.windowFrame(context, window.rect, colour) }
    ViewKit.ground(context, top: Self.middleBase, colour: colour.lit(-0.05))
    ViewKit.rect(context, CGRect(x: 60, y: 28.6, width: 4, height: 2.6), colour.lit(0.08))
    ViewKit.rect(
      context, CGRect(x: 61.2, y: 31.2, width: 1.6, height: 0.3), ViewPalette.porchRed, 0.6)
    let wire = colour.lit(-0.3)
    var hangers: [[CGPoint]] = []
    for x in [-30.0, 26, 82, 138] as [CGFloat] {
      hangers.append(ViewKit.pole(context, x: x, top: 6, base: Self.middleBase + 1, colour: wire))
    }
    for (left, right) in zip(hangers, hangers.dropFirst()) {
      for (from, to) in zip(left, right).prefix(3) {
        ViewKit.wire(context, from: from, to: to, sag: 3, colour: wire, width: 0.18)
      }
    }
  }

  static let storeWindow = CGRect(x: 66, y: 39, width: 18, height: 6)
  static let shelter = CGRect(x: 38, y: 39, width: 14, height: 9)
  static let shelterCat = ViewRoofCat(
    rhythm: ViewRhythm(seed: 251, slot: 150, chance: 0.9, length: 110...140),
    left: CGPoint(x: 30, y: streetBase - 0.2), ridge: CGPoint(x: 42, y: streetBase - 0.2),
    right: CGPoint(x: 58, y: streetBase - 0.2), plane: .street, size: 0.55)

  static func eyeShine(_ moment: ViewMoment) -> Double {
    guard moment.palette.lampsOn, let pass = roadway.cars.pass(at: moment.now) else { return 0 }
    return max(0, 1 - abs(Double(roadway.carX(pass) - shelterCat.ridge.x)) / 26)
  }

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let base = Self.streetBase
    ViewKit.ground(context, top: base - 1, colour: colour.lit(-0.04))
    let store = CGRect(x: 62, y: base - 15, width: 34, height: 15)
    ViewKit.rect(context, store, colour.lit(0.03))
    ViewKit.rect(context, CGRect(x: 61, y: base - 16, width: 36, height: 1.6), colour.lit(-0.1))
    ViewKit.rect(context, CGRect(x: 62, y: base - 13.4, width: 34, height: 2.4), colour.lit(-0.06))
    ViewKit.windowFrame(context, Self.storeWindow, colour)
    ViewKit.rect(context, CGRect(x: 88, y: base - 8, width: 4.5, height: 8), colour.lit(-0.3))
    ViewKit.pine(
      context, x: 30, base: base - 0.5, height: 18, colour: colour.lit(-0.08), look: look)
    ViewKit.house(
      context, x: -22, base: base, width: 26, wall: 13, roof: 7, colour: colour.lit(0.02),
      look: look)
    for window in Self.streetWindows { ViewKit.windowFrame(context, window.rect, colour) }
    ViewKit.rect(context, CGRect(x: 6, y: base - 9, width: 12, height: 9), colour.lit(0.01))
    ViewKit.rect(
      context, CGRect(x: 7, y: base - 7.6, width: 10, height: 7.6),
      colour.lit(look.isDark ? 0.06 : 0.12))
    let shelter = Self.shelter
    ViewKit.rect(
      context,
      CGRect(x: shelter.minX - 0.6, y: shelter.minY, width: shelter.width + 1.2, height: 0.8),
      colour.lit(-0.2))
    for x in [shelter.minX, shelter.maxX - 0.5] {
      ViewKit.rect(
        context, CGRect(x: x, y: shelter.minY, width: 0.5, height: shelter.height), colour.lit(-0.2)
      )
    }
    ViewKit.rect(
      context,
      CGRect(
        x: shelter.minX + 0.5, y: shelter.minY + 0.8, width: shelter.width - 1,
        height: shelter.height - 3), colour.lit(0.05), 0.45)
    ViewKit.rect(
      context, CGRect(x: shelter.minX + 2, y: shelter.maxY - 2.6, width: 8, height: 0.6),
      colour.lit(-0.2))
    ViewKit.rect(
      context, CGRect(x: -45, y: base, width: 190, height: 1.4),
      colour.lit(look.isDark ? 0.05 : 0.15))
    ViewKit.ground(
      context, top: base + 1.4, colour: colour.lit(-0.25).mixed(with: look.palette.skyTop, by: 0.15)
    )
    if look.weather == .snow {
      ViewKit.ground(
        context, top: base + 1.4, colour: ViewKit.snow(look).mixed(with: colour, by: 0.4))
    }
    ViewKit.streetLampPost(
      context, x: Self.lampHead.x + 5, top: Self.lampHead.y - 0.6, base: base + 1.2,
      colour: colour.lit(-0.25))
  }

  static let streetWindows: [ViewLitWindow] = [
    ViewLitWindow(id: 41, rect: CGRect(x: -16, y: 39, width: 4, height: 4.4), plane: .street),
    ViewLitWindow(id: 42, rect: CGRect(x: -6, y: 39, width: 4, height: 4.4), plane: .street),
    ViewLitWindow(id: 43, rect: CGRect(x: -10.6, y: 31.4, width: 3.2, height: 3), plane: .street),
  ]

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let top: CGFloat = 50
    ViewKit.rect(context, CGRect(x: -45, y: top, width: 190, height: 0.6), colour)
    var x: CGFloat = -44
    while x < 145 {
      ViewKit.rect(context, CGRect(x: x, y: top, width: 0.8, height: 16), colour)
      x += 18
    }
    var mesh = Path()
    var d: CGFloat = -60
    while d < 160 {
      mesh.move(to: CGPoint(x: d, y: top))
      mesh.addLine(to: CGPoint(x: d + 14, y: top + 14))
      mesh.move(to: CGPoint(x: d + 14, y: top))
      mesh.addLine(to: CGPoint(x: d, y: top + 14))
      d += 2.2
    }
    context.stroke(mesh, with: .color(colour.color(0.55)), lineWidth: 0.12)
    ViewKit.rect(context, CGRect(x: 103, y: -50, width: 1.8, height: 112), colour.lit(0.02))
    ViewKit.rect(context, CGRect(x: 102.4, y: 49, width: 3, height: 1.2), colour.lit(0.02))
  }

  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: farLife(context, moment: moment)
    case .middle: ViewWindows.draw(Self.middleWindows, context, moment: moment)
    case .street: streetLife(context, moment: moment)
    case .near: drip(context, moment: moment)
    }
  }

  private func farLife(_ context: GraphicsContext, moment: ViewMoment) {
    let lit = moment.palette.lampsOn
    for index in 0..<14 {
      let speed = 6 + 3 * ViewRhythm.hash(index, seed: 251)
      let phase = 200 * ViewRhythm.hash(index, seed: 252)
      let span = 200.0
      let along = (moment.now * speed + phase).truncatingRemainder(dividingBy: span)
      let east = index % 2 == 0
      let x = east ? -50 + along : 150 - along
      let colour = east ? ViewPalette.lampCore : ViewColour(0xFF3B3B)
      let y = Self.highway - (east ? 0.5 : 0.2)
      if lit {
        ViewKit.glow(context, CGPoint(x: x, y: y), 0.9, colour, 0.7)
      } else {
        ViewKit.rect(
          context, CGRect(x: x - 0.6, y: y - 0.3, width: 1.2, height: 0.5),
          moment.palette.far.lit(-0.2))
      }
    }
    if moment.look.isDark, (moment.now / 2.1).truncatingRemainder(dividingBy: 1) < 0.2 {
      ViewKit.glow(context, CGPoint(x: 88.4, y: 11.6), 2, ViewColour(0xFF3B3B), 0.85)
    }
    lightningFlash(context, moment: moment)
  }

  private func lightningFlash(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.weather == .rain, let pass = Self.lightning.pass(at: moment.now) else {
      return
    }
    let p = pass.progress
    let level = p < 0.15 ? 1 : p < 0.3 ? 0.2 : p < 0.45 ? 0.8 : max(0, 1 - (p - 0.45) / 0.55) * 0.5
    let plate = ViewStage.plate
    context.fill(Path(plate), with: .color(ViewColour(0xDDE6FF).color(0.28 * level)))
    var bolt = Path()
    var point = CGPoint(x: 20 + 70 * pass.variant, y: -30)
    bolt.move(to: point)
    for step in 0..<7 {
      point.x += CGFloat(ViewRhythm.hash(Int(pass.index) * 9 + step, seed: 261) - 0.5) * 8
      point.y += 8.6
      bolt.addLine(to: point)
    }
    context.stroke(bolt, with: .color(ViewColour(0xF4F6FF).color(level)), lineWidth: 0.5)
    context.stroke(bolt, with: .color(ViewColour(0xB8C8FF).color(0.4 * level)), lineWidth: 2)
  }

  private func streetLife(_ context: GraphicsContext, moment: ViewMoment) {
    let lamps = moment.lamps
    ViewWindows.draw(Self.streetWindows, context, moment: moment)
    ViewKit.circle(context, Self.porch, 0.4, ViewPalette.lampCore, lamps)
    ViewKit.glow(context, Self.porch, 3.6, ViewPalette.lamp, 0.45 * lamps)
    let window = Self.storeWindow
    let hum = 0.92 + 0.08 * sin(moment.now * 37) * sin(moment.now * 3.3)
    let tube = ViewColour(0xFFF2D8)
    context.fill(Path(window), with: .color(tube.color((moment.look.isDark ? 0.62 : 0.3) * hum)))
    ViewKit.glow(
      context, CGPoint(x: window.midX, y: window.maxY), 14, ViewPalette.lamp,
      0.3 * hum * (moment.look.isDark ? 1 : 0.3))
    let packs = [0xE5503A, 0xFFD166, 0x3DDC84, 0x5BA8FF, 0xFF8A3D].map(ViewColour.init)
    for shelf in 0..<2 {
      let y = window.minY + 1.4 + CGFloat(shelf) * 2.4
      ViewKit.rect(
        context, CGRect(x: window.minX + 0.6, y: y + 1, width: window.width - 1.2, height: 0.3),
        moment.palette.street.lit(-0.1), 0.6)
      for item in 0..<11 {
        let colour = packs[(item * 3 + shelf) % packs.count].mixed(with: tube, by: 0.35)
        ViewKit.rect(
          context, CGRect(x: window.minX + 1 + CGFloat(item) * 1.5, y: y, width: 1, height: 1),
          colour, 0.75 * hum)
      }
    }
    if moment.look.isDark {
      let neon = (moment.now * 0.5).truncatingRemainder(dividingBy: 9) < 8.6
      let cup = CGPoint(x: 94, y: 37)
      if neon {
        var outline = Path()
        outline.addRoundedRect(
          in: CGRect(x: cup.x - 1.4, y: cup.y - 1.2, width: 2.8, height: 2.6),
          cornerSize: CGSize(width: 0.6, height: 0.6))
        outline.addEllipse(in: CGRect(x: cup.x + 1.2, y: cup.y - 0.6, width: 1.2, height: 1.2))
        context.stroke(outline, with: .color(ViewColour(0xFF5FA2).color()), lineWidth: 0.3)
        ViewKit.glow(context, cup, 4, ViewColour(0xFF5FA2), 0.35)
      }
    }
    let panel = CGRect(
      x: Self.shelter.maxX - 5, y: Self.shelter.minY + 1.6, width: 3.8, height: 5.4)
    context.fill(
      Path(panel), with: .color(ViewColour(0xE8F0FF).color(moment.look.isDark ? 0.75 : 0.4)))
    ViewKit.glow(
      context, CGPoint(x: panel.midX, y: panel.midY), 6, ViewColour(0xC8DAFF), 0.25 * lamps)
    Self.lamp.draw(context, moment: moment)
    puddles(context, moment: moment)
    Self.shelterCat.draw(context, moment: moment, eyeShine: Self.eyeShine(moment))
    walker(context, moment: moment)
    Self.roadway.draw(context, moment: moment)
  }

  private func puddles(_ context: GraphicsContext, moment: ViewMoment) {
    let spots: [CGRect] = [
      CGRect(x: 20, y: 50.6, width: 12, height: 1.4), CGRect(x: 54, y: 50.2, width: 9, height: 1.2),
      CGRect(x: 80, y: 51, width: 14, height: 1.5),
    ]
    let gloss = moment.palette.skyMiddle.lit(0.3)
    for (index, spot) in spots.enumerated() {
      context.fill(Path(ellipseIn: spot), with: .color(gloss.color(0.18)))
      guard moment.look.weather == .rain else { continue }
      for ring in 0..<3 {
        let seed = index * 3 + ring
        let cycle = 0.9 + 0.6 * ViewRhythm.hash(seed, seed: 271)
        let t = moment.now / cycle + ViewRhythm.hash(seed, seed: 272)
        let p = t.truncatingRemainder(dividingBy: 1)
        let slot = Int(t)
        let x = spot.minX + spot.width * CGFloat(ViewRhythm.hash(slot &* 7 &+ seed, seed: 273))
        let r = 0.3 + 1.6 * CGFloat(p)
        context.stroke(
          Path(ellipseIn: CGRect(x: x - r, y: spot.midY - r * 0.3, width: 2 * r, height: r * 0.6)),
          with: .color(gloss.lit(0.3).color(0.5 * (1 - p))), lineWidth: 0.12)
      }
    }
  }

  private func walker(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = Self.walker.pass(at: moment.now) else { return }
    let point = Self.walkerPoint(pass)
    let colour = moment.palette.street.lit(-0.4)
    let step = sin(moment.now * 6) * 0.5
    var person = context
    person.translateBy(x: point.x, y: point.y)
    person.fill(
      Path(roundedRect: CGRect(x: -0.9, y: -5.6, width: 1.8, height: 3.6), cornerRadius: 0.7),
      with: .color(colour.color()))
    person.fill(
      Path(ellipseIn: CGRect(x: -0.6, y: -6.8, width: 1.2, height: 1.3)),
      with: .color(colour.color()))
    for (x, phase) in [(-0.6, step), (0.2, -step)] as [(CGFloat, CGFloat)] {
      person.fill(
        Path(CGRect(x: x + phase * 0.6, y: -2.1, width: 0.45, height: 2.1)),
        with: .color(colour.color()))
    }
    let canopy = ViewColour([0xE5503A, 0xFFD166, 0x3DDC84, 0x5BA8FF][Int(pass.variant * 11) % 4])
    var umbrella = person
    umbrella.rotate(by: .degrees(pass.variant < 0.5 ? 8 : -8))
    var dome = Path()
    dome.move(to: CGPoint(x: -3, y: -7))
    dome.addQuadCurve(to: CGPoint(x: 3, y: -7), control: CGPoint(x: 0, y: -10.4))
    dome.closeSubpath()
    umbrella.fill(
      dome,
      with: .color(
        canopy.mixed(with: moment.palette.street, by: moment.look.isDark ? 0.45 : 0.15).color()))
    umbrella.fill(
      Path(CGRect(x: -0.08, y: -7, width: 0.16, height: 3)), with: .color(colour.color()))
  }

  static func walkerPoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    let p = CGFloat(pass.progress)
    return CGPoint(x: pass.variant < 0.5 ? -40 + 180 * p : 140 - 180 * p, y: streetBase + 0.9)
  }

  private func drip(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.weather == .rain else { return }
    let colour = moment.palette.skyMiddle.lit(0.5)
    for index in 0..<4 {
      let p = (moment.now * 1.3 + Double(index) / 4).truncatingRemainder(dividingBy: 1)
      ViewKit.circle(context, CGPoint(x: 104.2, y: 50.4 + 9 * p * p), 0.28, colour, 0.6 * (1 - p))
    }
  }

  // MARK: - What the cat sees

  func headlight(at now: Double) -> ViewHeadlight? { Self.roadway.headlight(at: now) }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if let cat = Self.shelterCat.interest(at: moment.now) { return cat }
    if let car = Self.roadway.interest(at: moment.now) { return car }
    if let pass = Self.walker.pass(at: moment.now) {
      let point = Self.walkerPoint(pass)
      if point.x > 0, point.x < 100 {
        return ViewInterest(point: point, plane: .street, paw: false, id: pass.index)
      }
    }
    return nil
  }
}
