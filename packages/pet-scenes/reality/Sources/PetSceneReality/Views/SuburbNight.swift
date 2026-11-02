import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// View 1, the pilot: a US suburb at night. Far: low hills, the water tower, a radio mast and a
/// scatter of far-off windows. Middle: the row of roofs behind the street under the power lines.
/// Street: the houses across the road, a car on a driveway, the street lamp. Near: a fence and a
/// branch just outside. The note is taped over the middle, so the hero shapes stand to its sides.
struct SuburbNight: ViewRecipe {
  /// The road the cars drive along, in stage units.
  static let road: CGFloat = 51.9
  static let lampHead = CGPoint(x: 92, y: 12)
  static let tower = CGPoint(x: 10, y: 2)
  static let cars = ViewRhythm(seed: 21, slot: 16, chance: 0.75, length: 3.6...5.4)
  static let roofCat = ViewRhythm(seed: 33, slot: 140, chance: 0.55, length: 40...70)
  /// The roof the cat walks: its left eave, ridge and right eave.
  static let roofPath = (
    left: CGPoint(x: 72.4, y: 31.7), ridge: CGPoint(x: 85, y: 24.3),
    right: CGPoint(x: 97.6, y: 31.7)
  )

  var moon: CGPoint { CGPoint(x: 78, y: -14) }
  var livePlanes: Set<ViewPlane> { [.far, .middle, .street, .near] }

  // MARK: - Still planes

  func paint(_ plane: ViewPlane, _ context: GraphicsContext, look: ViewLook) {
    let palette = look.palette
    let colour = palette.colour(plane)
    switch plane {
    case .far: paintFar(context, colour: colour, look: look)
    case .middle: paintMiddle(context, colour: colour, look: look)
    case .street: paintStreet(context, colour: colour, look: look)
    case .near: paintNear(context, colour: colour, look: look)
    }
  }

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let palette = look.palette
    ViewKit.hills(
      context, base: 37, waves: [3, 5, 2.5, 6, 3.5, 4.5, 2, 5],
      colour: colour.lit(look.isDark ? 0.05 : 0.08))
    ViewKit.ground(context, top: 37, colour: colour)
    // A far-off town: little blocks along the foot of the hills, a few lit.
    for index in 0..<46 {
      let x = -40 + CGFloat(index) * 4 + CGFloat(ViewRhythm.hash(index, seed: 5)) * 2
      let height = 1 + CGFloat(ViewRhythm.hash(index, seed: 6)) * 2.2
      ViewKit.rect(
        context, CGRect(x: x, y: 37 - height, width: 3, height: height), colour.lit(-0.06))
      if look.isDark, ViewRhythm.hash(index, seed: 7) < palette.litShare * 0.9 {
        ViewKit.rect(
          context, CGRect(x: x + 1, y: 37 - height + 0.5, width: 0.6, height: 0.6),
          ViewPalette.lamp, 0.75)
      }
    }
    if look.weather == .snow {
      ViewKit.rect(context, CGRect(x: -45, y: 37, width: 190, height: 0.8), ViewKit.snow(look), 0.5)
    }
    ViewKit.waterTower(
      context, x: Self.tower.x, top: Self.tower.y, base: 38, size: 13, colour: colour.lit(-0.24),
      look: look)
    // A radio mast: a thin lattice with a red light on top, drawn by the life.
    var mast = Path()
    mast.move(to: CGPoint(x: 68.4, y: 37))
    mast.addLine(to: CGPoint(x: 69.5, y: 9))
    mast.addLine(to: CGPoint(x: 70.6, y: 37))
    context.stroke(mast, with: .color(colour.lit(-0.1).color()), lineWidth: 0.35)
    for share in stride(from: 0.15, to: 0.95, by: 0.14) {
      let y = 9 + 28 * share
      let half = 0.15 + 1.1 * share * 0.5
      var rung = Path()
      rung.move(to: CGPoint(x: 69.5 - half, y: y))
      rung.addLine(to: CGPoint(x: 69.5 + half, y: y + 1.6))
      context.stroke(rung, with: .color(colour.lit(-0.1).color()), lineWidth: 0.15)
    }
  }

  /// The row of houses behind the street, with their lit windows.
  static let middleHouses:
    [(x: CGFloat, width: CGFloat, wall: CGFloat, roof: CGFloat, shade: Double)] = [
      (-36, 18, 8, 5.5, 0.02), (-14, 17, 9, 6.5, -0.03), (8, 20, 7.5, 5.2, 0.03),
      (32, 17, 8.5, 6, -0.02), (52, 18, 8, 5.8, 0.04), (73, 24, 9, 7.4, -0.01),
      (101, 19, 8.2, 5.6, 0.02), (125, 17, 9, 6.2, -0.03),
    ]
  static let middleBase: CGFloat = 40.5

  static let middleWindows: [ViewLitWindow] = middleHouses.enumerated().flatMap { index, house in
    let eave = middleBase - house.wall
    return [
      ViewLitWindow(
        id: 100 + index * 2,
        rect: CGRect(x: house.x + house.width * 0.2, y: eave + 2, width: 2.2, height: 2.6),
        plane: .middle),
      ViewLitWindow(
        id: 101 + index * 2,
        rect: CGRect(x: house.x + house.width * 0.62, y: eave + 2, width: 2.2, height: 2.6),
        plane: .middle),
    ]
  }

  static let poles: [CGFloat] = [-24, 30, 84, 138]
  static let poleTop: CGFloat = 5

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    for (index, tree) in [(-20.0, 9.0), (5, 10), (30, 8.5), (50, 9.5), (99, 10), (123, 9)]
      .enumerated()
    {
      ViewKit.tree(
        context, x: tree.0, base: Self.middleBase, size: tree.1, colour: colour.lit(-0.04),
        seed: index, look: look)
    }
    for (index, house) in Self.middleHouses.enumerated() {
      let shade = colour.lit(house.shade)
      if index % 3 == 1 {
        ViewKit.rect(
          context,
          CGRect(
            x: house.x + house.width * 0.68, y: Self.middleBase - house.wall - house.roof * 0.9,
            width: 1.6, height: house.roof), shade.lit(-0.1))
      }
      ViewKit.house(
        context, x: house.x, base: Self.middleBase, width: house.width, wall: house.wall,
        roof: house.roof, colour: shade, look: look)
    }
    for window in Self.middleWindows { ViewKit.windowFrame(context, window.rect, colour) }
    ViewKit.ground(context, top: Self.middleBase, colour: colour.lit(-0.05))
    if look.weather == .snow {
      ViewKit.ground(
        context, top: Self.middleBase, colour: ViewKit.snow(look).mixed(with: colour, by: 0.35))
    }
    let wireColour = colour.lit(-0.3)
    var hangers: [[CGPoint]] = []
    for x in Self.poles {
      hangers.append(
        ViewKit.pole(
          context, x: x, top: Self.poleTop, base: Self.middleBase + 1, colour: wireColour))
    }
    for (left, right) in zip(hangers, hangers.dropFirst()) {
      for (index, (from, to)) in zip(left, right).enumerated() {
        ViewKit.wire(
          context, from: from, to: to, sag: index < 3 ? 2.6 : 3.4, colour: wireColour, width: 0.18)
      }
    }
    // Three birds asleep on the top wire.
    let (from, to) = (hangers[1][0], hangers[2][0])
    for share in [0.22, 0.26, 0.71] as [CGFloat] {
      let point = ViewKit.onWire(from: from, to: to, sag: 2.6, share: share)
      ViewKit.circle(context, CGPoint(x: point.x, y: point.y - 0.55), 0.55, wireColour)
      ViewKit.circle(context, CGPoint(x: point.x + 0.45, y: point.y - 1.05), 0.32, wireColour)
    }
  }

  static let streetBase: CGFloat = 48

  static let streetWindows: [ViewLitWindow] = [
    ViewLitWindow(id: 1, rect: CGRect(x: -9, y: 38.0, width: 4, height: 4.6), plane: .street),
    ViewLitWindow(id: 2, rect: CGRect(x: 4, y: 38.0, width: 4, height: 4.6), plane: .street),
    ViewLitWindow(id: 3, rect: CGRect(x: -2.2, y: 28.6, width: 3.4, height: 3.4), plane: .street),
    ViewLitWindow(id: 4, rect: CGRect(x: 64.5, y: 37.0, width: 4.2, height: 4.8), plane: .street),
    ViewLitWindow(
      id: 5, rect: CGRect(x: 75, y: 37.0, width: 4.2, height: 4.8), plane: .street, isTV: true),
    ViewLitWindow(id: 6, rect: CGRect(x: 70.3, y: 26.6, width: 3.6, height: 3.6), plane: .street),
    ViewLitWindow(id: 7, rect: CGRect(x: 117, y: 38.0, width: 4, height: 4.6), plane: .street),
    ViewLitWindow(id: 8, rect: CGRect(x: 127, y: 38.0, width: 4, height: 4.6), plane: .street),
  ]

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let palette = look.palette
    let base = Self.streetBase
    let lawn = colour.lit(-0.04)
    ViewKit.ground(context, top: base - 1, colour: lawn)
    if look.weather == .snow {
      ViewKit.ground(
        context, top: base - 1, colour: ViewKit.snow(look).mixed(with: colour, by: 0.2))
    }
    ViewKit.tree(
      context, x: 45, base: base - 0.5, size: 13, colour: colour.lit(-0.06), seed: 9, look: look)
    ViewKit.pine(
      context, x: 106, base: base - 0.5, height: 22, colour: colour.lit(-0.08), look: look)
    ViewKit.house(
      context, x: -14, base: base, width: 27, wall: 14, roof: 9, colour: colour.lit(0.03),
      look: look)
    ViewKit.house(
      context, x: 61, base: base, width: 22, wall: 15, roof: 9.5, colour: colour.lit(0.02),
      look: look)
    // The garage beside the right-hand house, its door a shade lighter.
    ViewKit.rect(context, CGRect(x: 83, y: base - 9.5, width: 11, height: 9.5), colour.lit(0.01))
    ViewKit.rect(
      context, CGRect(x: 84, y: base - 8, width: 9, height: 8),
      colour.lit(look.isDark ? 0.07 : 0.12))
    for row in 1..<4 {
      ViewKit.rect(
        context, CGRect(x: 84, y: base - 8 + CGFloat(row) * 2, width: 9, height: 0.18),
        colour.lit(-0.05))
    }
    ViewKit.house(
      context, x: 113, base: base, width: 24, wall: 14, roof: 8.5, colour: colour.lit(0.03),
      look: look)
    for window in Self.streetWindows { ViewKit.windowFrame(context, window.rect, colour) }
    // Doors under their porch lights.
    for door in [
      CGRect(x: 10, y: base - 6.6, width: 3, height: 6.6),
      CGRect(x: 70.6, y: base - 7, width: 3, height: 7),
    ] {
      ViewKit.rect(context, door, colour.lit(-0.3))
    }
    ViewKit.car(context, x: 50, base: base, length: 13, body: colour.lit(-0.12))
    // Mailbox by the kerb.
    ViewKit.rect(
      context, CGRect(x: 58.2, y: base - 4.4, width: 0.6, height: 4.4), colour.lit(-0.25))
    context.fill(
      Path(roundedRect: CGRect(x: 57, y: base - 5.8, width: 3.2, height: 1.9), cornerRadius: 0.9),
      with: .color(colour.lit(-0.2).color()))
    ViewKit.fence(
      context, from: 22, to: 38, base: base, height: 3.6, colour: colour.lit(-0.1), look: look)
    // Sidewalk, kerb and road, with a dashed middle line.
    ViewKit.rect(
      context, CGRect(x: -45, y: base, width: 190, height: 1.4),
      colour.lit(look.isDark ? 0.05 : 0.15))
    let road = colour.lit(-0.22).mixed(with: palette.skyTop, by: 0.1)
    ViewKit.ground(context, top: base + 1.4, colour: road)
    var x: CGFloat = -44
    while x < 145 {
      ViewKit.rect(
        context, CGRect(x: x, y: Self.road + 3.2, width: 3.6, height: 0.35), ViewColour(0xE8D28A),
        look.isDark ? 0.25 : 0.4)
      x += 8
    }
    if look.weather == .snow {
      ViewKit.ground(
        context, top: base + 1.4, colour: ViewKit.snow(look).mixed(with: road, by: 0.45))
    }
    ViewKit.streetLampPost(
      context, x: Self.lampHead.x + 5, top: Self.lampHead.y - 0.6, base: base + 1.2,
      colour: colour.lit(-0.25))
  }

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    ViewKit.fence(context, from: -44, to: 22, base: 60, height: 9, colour: colour, look: look)
    ViewKit.rect(context, CGRect(x: 18, y: 48.5, width: 1.2, height: 12), colour)
    context.fill(
      Path(roundedRect: CGRect(x: 15.8, y: 45.9, width: 5.6, height: 3.2), cornerRadius: 1.5),
      with: .color(colour.lit(0.02).color()))
    ViewKit.rect(
      context, CGRect(x: 21.1, y: 46.3, width: 0.4, height: 1.8), ViewPalette.porchRed,
      look.isDark ? 0.55 : 0.85)
    // A hedge along the bottom right, round tops.
    for index in 0..<9 {
      let x = 58 + CGFloat(index) * 9.5
      ViewKit.circle(
        context, CGPoint(x: x, y: 60 - CGFloat(ViewRhythm.hash(index, seed: 91)) * 1.5), 6,
        colour.lit(0.02))
    }
    ViewKit.ground(context, top: 60, colour: colour)
  }

  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: farLife(context, moment: moment)
    case .middle:
      ViewWindows.draw(Self.middleWindows, context, moment: moment)
      roofCat(context, moment: moment)
    case .street: streetLife(context, moment: moment)
    case .near: branch(context, moment: moment)
    }
  }

  private func farLife(_ context: GraphicsContext, moment: ViewMoment) {
    // The mast's red light, slow and steady, and the tower's own small lamp.
    let blink = (moment.now / 1.7).truncatingRemainder(dividingBy: 1) < 0.22
    if moment.look.isDark, blink {
      ViewKit.glow(context, CGPoint(x: 69.5, y: 8.6), 2.2, ViewColour(0xFF3B3B), 0.9)
      ViewKit.circle(context, CGPoint(x: 69.5, y: 8.6), 0.35, ViewColour(0xFF6B6B))
    }
    if moment.lamps > 0 {
      ViewKit.glow(
        context, CGPoint(x: Self.tower.x, y: Self.tower.y + 1.2), 2.6, ViewColour(0xFF3B3B),
        0.6 * moment.lamps)
    }
  }

  static let porches = [CGPoint(x: 15, y: 40.4), CGPoint(x: 75.6, y: 40)]

  private func streetLife(_ context: GraphicsContext, moment: ViewMoment) {
    let lamps = moment.lamps
    ViewWindows.draw(Self.streetWindows, context, moment: moment)
    // Porch lights by the doors, always on at night.
    for porch in Self.porches {
      ViewKit.circle(context, porch, 0.4, ViewPalette.lampCore, lamps)
      ViewKit.glow(context, porch, 3.4, ViewPalette.lamp, 0.4 * lamps)
    }
    fairyLights(context, moment: moment)
    streetLamp(context, moment: moment)
    if let pass = Self.cars.pass(at: moment.now) { car(context, pass: pass, moment: moment) }
    moth(context, moment: moment)
  }

  /// A string of warm bulbs along the right-hand house's eave, each breathing on its own.
  private func fairyLights(_ context: GraphicsContext, moment: ViewMoment) {
    let from = CGPoint(x: 60.5, y: Self.streetBase - 14.4)
    let to = CGPoint(x: 83.5, y: Self.streetBase - 14.4)
    ViewKit.wire(
      context, from: from, to: to, sag: 0.9, colour: moment.palette.street.lit(-0.3), width: 0.15)
    let lamps = moment.lamps
    guard lamps > 0 else { return }
    for index in 0..<12 {
      let point = ViewKit.onWire(from: from, to: to, sag: 0.9, share: (CGFloat(index) + 0.5) / 12)
      let breath =
        0.75 + 0.25
        * sin(moment.now * (0.9 + 0.5 * ViewRhythm.hash(index, seed: 51)) + Double(index))
      let colour = index % 4 == 1 ? ViewColour(0xFFB27A) : ViewPalette.lampCore
      ViewKit.circle(context, CGPoint(x: point.x, y: point.y + 0.4), 0.3, colour, lamps)
      ViewKit.glow(
        context, CGPoint(x: point.x, y: point.y + 0.4), 1.6, ViewPalette.lamp, 0.45 * breath * lamps
      )
    }
  }

  private func streetLamp(_ context: GraphicsContext, moment: ViewMoment) {
    let level = moment.lamps
    let head = Self.lampHead
    context.fill(
      Path(
        roundedRect: CGRect(x: head.x - 1.8, y: head.y - 0.6, width: 3.6, height: 1.3),
        cornerRadius: 0.6),
      with: .color((level > 0.5 ? ViewPalette.lampCore : moment.palette.street.lit(0.1)).color()))
    guard level > 0 else { return }
    var cone = Path()
    cone.move(to: CGPoint(x: head.x - 1.4, y: head.y + 0.5))
    cone.addLine(to: CGPoint(x: head.x - 10, y: Self.road + 1))
    cone.addLine(to: CGPoint(x: head.x + 10, y: Self.road + 1))
    cone.addLine(to: CGPoint(x: head.x + 1.4, y: head.y + 0.5))
    cone.closeSubpath()
    let foggy = moment.look.weather == .fog || moment.look.weather == .rain
    context.fill(
      cone,
      with: .linearGradient(
        Gradient(colors: [
          ViewPalette.lamp.color((foggy ? 0.42 : 0.3) * level),
          ViewPalette.lamp.color(0.03 * level),
        ]),
        startPoint: head, endPoint: CGPoint(x: head.x, y: Self.road + 1)))
    ViewKit.glow(context, head, foggy ? 9 : 6, ViewPalette.lamp, 0.55 * level)
    // The pool of light on the pavement, and its shine down a wet road.
    context.fill(
      Path(ellipseIn: CGRect(x: head.x - 11, y: Self.streetBase - 0.6, width: 22, height: 3.4)),
      with: .radialGradient(
        Gradient(colors: [ViewPalette.lamp.color(0.32 * level), ViewPalette.lamp.color(0)]),
        center: CGPoint(x: head.x, y: Self.streetBase + 1), startRadius: 0, endRadius: 11))
    if moment.look.weather == .rain {
      for (x, alpha) in [(head.x, 0.35), (Self.porches[0].x, 0.2), (Self.porches[1].x, 0.2)]
        as [(CGFloat, Double)]
      {
        context.fill(
          Path(CGRect(x: x - 0.9, y: Self.streetBase + 2, width: 1.8, height: 9)),
          with: .linearGradient(
            Gradient(colors: [ViewPalette.lamp.color(alpha * level), ViewPalette.lamp.color(0)]),
            startPoint: CGPoint(x: x, y: Self.streetBase + 2),
            endPoint: CGPoint(x: x, y: Self.streetBase + 11)))
      }
    }
  }

  /// Where a passing car is, in stage units.
  static func carX(_ pass: ViewRhythm.Pass) -> CGFloat {
    let leftToRight = pass.variant < 0.5
    let progress = CGFloat(pass.progress)
    return leftToRight ? -48 + 196 * progress : 148 - 196 * progress
  }

  private func car(_ context: GraphicsContext, pass: ViewRhythm.Pass, moment: ViewMoment) {
    let leftToRight = pass.variant < 0.5
    let x = Self.carX(pass)
    let length: CGFloat = 13
    let body = moment.palette.street.lit(-0.3).mixed(
      with: ViewColour([0x5A2430, 0x23324A, 0x3A3A40, 0x6A6A70][Int(pass.variant * 7) % 4]), by: 0.4
    )
    let lit = moment.palette.lampsOn
    let nose = leftToRight ? x + length / 2 : x - length / 2
    let tail = leftToRight ? x - length / 2 : x + length / 2
    if lit {
      // The beams reach ahead along the road and sweep the house fronts as they pass.
      let reach: CGFloat = leftToRight ? 30 : -30
      var beam = Path()
      beam.move(to: CGPoint(x: nose, y: Self.road - 1.6))
      beam.addLine(to: CGPoint(x: nose + reach, y: Self.road - 4.5))
      beam.addLine(to: CGPoint(x: nose + reach, y: Self.road + 2.6))
      beam.addLine(to: CGPoint(x: nose, y: Self.road - 0.6))
      beam.closeSubpath()
      context.fill(
        beam,
        with: .linearGradient(
          Gradient(colors: [ViewPalette.lampCore.color(0.5), ViewPalette.lampCore.color(0)]),
          startPoint: CGPoint(x: nose, y: Self.road),
          endPoint: CGPoint(x: nose + reach, y: Self.road)))
      let wash = CGPoint(x: nose + reach * 0.7, y: Self.streetBase - 6)
      ViewKit.glow(context, wash, 9, ViewPalette.lampCore, 0.16)
    }
    ViewKit.car(
      context, x: x - length / 2, base: Self.road + 1.6, length: length, body: body,
      facingLeft: !leftToRight)
    if lit {
      ViewKit.circle(context, CGPoint(x: nose, y: Self.road - 1.1), 0.5, ViewPalette.lampCore)
      ViewKit.glow(context, CGPoint(x: nose, y: Self.road - 1.1), 2.6, ViewPalette.lampCore, 0.7)
      ViewKit.glow(context, CGPoint(x: tail, y: Self.road - 1.1), 1.8, ViewColour(0xFF3B3B), 0.75)
    }
  }

  /// A moth around the street lamp's head: three slow waves that never line up the same way.
  private func moth(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.lamps > 0.5 else { return }
    let t = moment.now
    let head = Self.lampHead
    let x = head.x + 2.4 * sin(t * 2.3) + 1.1 * sin(t * 5.9 + 1) + 0.5 * sin(t * 11.3)
    let y = head.y + 2.2 + 1.2 * cos(t * 3.1) + 0.7 * sin(t * 7.3 + 2)
    let flap = 0.25 + 0.15 * abs(sin(t * 31))
    ViewKit.circle(context, CGPoint(x: x, y: y), flap, ViewPalette.lampCore, 0.85)
  }

  /// Now and then a cat climbs one roof, sits a while at the ridge, and goes down the far side.
  private func roofCat(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = Self.roofCat.pass(at: moment.now) else { return }
    let (point, sitting, facing) = Self.roofCatPose(pass)
    let colour = moment.palette.middle.lit(-0.45)
    let unit: CGFloat = 0.42
    var shape = context
    shape.translateBy(x: point.x, y: point.y)
    shape.scaleBy(x: facing * unit, y: unit)
    if sitting {
      shape.fill(
        Path(ellipseIn: CGRect(x: -1.6, y: -4.2, width: 3.2, height: 4.2)),
        with: .color(colour.color()))
      shape.fill(
        Path(ellipseIn: CGRect(x: -1.4, y: -6.4, width: 2.8, height: 2.6)),
        with: .color(colour.color()))
      for side in [-1.0, 1.0] as [CGFloat] {
        var ear = Path()
        ear.move(to: CGPoint(x: side * 1.2, y: -5.6))
        ear.addLine(to: CGPoint(x: side * 1.0, y: -7.3))
        ear.addLine(to: CGPoint(x: side * 0.3, y: -6.2))
        ear.closeSubpath()
        shape.fill(ear, with: .color(colour.color()))
      }
      var tail = Path()
      let swish = sin(moment.now * 1.3) * 1.2
      tail.move(to: CGPoint(x: -1.2, y: -0.4))
      tail.addQuadCurve(to: CGPoint(x: -3.6, y: -2.2 + swish), control: CGPoint(x: -3.8, y: 0.2))
      shape.stroke(tail, with: .color(colour.color()), lineWidth: 0.7)
    } else {
      let step = sin(moment.now * 9) * 0.5
      shape.fill(
        Path(ellipseIn: CGRect(x: -2.6, y: -3.6, width: 5.2, height: 2.4)),
        with: .color(colour.color()))
      shape.fill(
        Path(ellipseIn: CGRect(x: 1.8, y: -5, width: 2.4, height: 2.2)),
        with: .color(colour.color()))
      var ear = Path()
      ear.move(to: CGPoint(x: 2.6, y: -4.6))
      ear.addLine(to: CGPoint(x: 3, y: -5.9))
      ear.addLine(to: CGPoint(x: 3.6, y: -4.6))
      shape.fill(ear, with: .color(colour.color()))
      for (x, phase) in [(-1.8, step), (1.6, -step)] as [(CGFloat, CGFloat)] {
        shape.fill(
          Path(CGRect(x: x + phase, y: -1.6, width: 0.6, height: 1.6)), with: .color(colour.color())
        )
      }
      var tail = Path()
      tail.move(to: CGPoint(x: -2.4, y: -2.8))
      tail.addQuadCurve(to: CGPoint(x: -4.4, y: -5.6), control: CGPoint(x: -4.6, y: -2.6))
      shape.stroke(tail, with: .color(colour.color()), lineWidth: 0.7)
    }
  }

  /// Where the roof cat is: walking up for the first fifth, sitting at the ridge, then walking
  /// down the far side for the last fifth. `facing` is 1 for right and -1 for left.
  static func roofCatPose(_ pass: ViewRhythm.Pass) -> (CGPoint, sitting: Bool, facing: CGFloat) {
    let path = roofPath
    let fromLeft = pass.variant < 0.5
    let (start, end) = fromLeft ? (path.left, path.right) : (path.right, path.left)
    let facing: CGFloat = fromLeft ? 1 : -1
    let p = CGFloat(pass.progress)
    func along(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
      CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
    switch p {
    case ..<0.2: return (along(start, path.ridge, p / 0.2), false, facing)
    case ..<0.8: return (path.ridge, true, facing)
    default: return (along(path.ridge, end, (p - 0.8) / 0.2), false, facing)
    }
  }

  /// A branch reaching in from the top right corner, swaying in the wind.
  private func branch(_ context: GraphicsContext, moment: ViewMoment) {
    let colour = moment.palette.near
    let wind = moment.look.weather == .rain ? 1.8 : 1
    let t = moment.now
    let sway = CGFloat((0.6 * sin(t * 0.7) + 0.3 * sin(t * 1.9 + 1) + 0.15 * sin(t * 4.3)) * wind)
    var branch = context
    branch.translateBy(x: 116, y: -10)
    branch.scaleBy(x: 1.3, y: 1.3)
    branch.rotate(by: .degrees(Double(sway) * 1.6))
    let twigs: [(CGPoint, CGPoint, CGPoint)] = [
      (.zero, CGPoint(x: -36, y: 13), CGPoint(x: -16, y: 1)),
      (CGPoint(x: -14, y: 3.4), CGPoint(x: -24, y: -3), CGPoint(x: -19, y: 2)),
      (CGPoint(x: -24, y: 8.2), CGPoint(x: -30, y: 17), CGPoint(x: -26, y: 13)),
      (CGPoint(x: -6, y: 1.2), CGPoint(x: -10, y: 9), CGPoint(x: -9, y: 4)),
    ]
    for (index, twig) in twigs.enumerated() {
      var stem = Path()
      stem.move(to: twig.0)
      stem.addQuadCurve(to: twig.1, control: twig.2)
      branch.stroke(stem, with: .color(colour.color()), lineWidth: index == 0 ? 1.1 : 0.5)
      // Leaves in pairs along each twig, each its own small flutter.
      for step in 1...7 {
        let share = CGFloat(step) / 7.5
        let u = 1 - share
        let point = CGPoint(
          x: u * u * twig.0.x + 2 * u * share * twig.2.x + share * share * twig.1.x,
          y: u * u * twig.0.y + 2 * u * share * twig.2.y + share * share * twig.1.y)
        for side in [-1.0, 1.0] {
          let seed = index * 40 + step * 2 + (side > 0 ? 1 : 0)
          let flutter = sin(t * (1.8 + ViewRhythm.hash(seed, seed: 95)) + Double(seed)) * 12 * wind
          let angle = side * 55 + flutter + 25 * ViewRhythm.hash(seed, seed: 96)
          var leaf = branch
          leaf.translateBy(x: point.x, y: point.y)
          leaf.rotate(by: .degrees(angle))
          let length = 2.2 + 1.2 * CGFloat(ViewRhythm.hash(seed, seed: 97))
          leaf.fill(
            Path(ellipseIn: CGRect(x: 0, y: -length * 0.22, width: length, height: length * 0.44)),
            with: .color(colour.lit(seed % 3 == 0 ? 0.05 : 0).color()))
          if moment.look.weather == .snow, seed % 4 == 0 {
            leaf.fill(
              Path(
                ellipseIn: CGRect(
                  x: 0.2, y: -length * 0.3, width: length * 0.7, height: length * 0.2)),
              with: .color(ViewKit.snow(moment.look).color(0.8)))
          }
        }
      }
    }
  }

  // MARK: - What the cat sees

  func headlight(at now: Double) -> ViewHeadlight? {
    guard let pass = Self.cars.pass(at: now) else { return nil }
    return ViewHeadlight(progress: pass.progress, leftToRight: pass.variant < 0.5)
  }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if let pass = Self.cars.pass(at: moment.now) {
      let x = Self.carX(pass)
      if x > -5, x < 105 {
        return ViewInterest(
          point: CGPoint(x: x, y: Self.road), plane: .street, paw: false, id: pass.index)
      }
    }
    // The roof cat is watched while it climbs and leaves, not for the whole of its sit.
    if let pass = Self.roofCat.pass(at: moment.now), pass.progress < 0.3 || pass.progress > 0.8 {
      return ViewInterest(
        point: Self.roofCatPose(pass).0, plane: .middle, paw: false, id: pass.index)
    }
    return nil
  }
}
