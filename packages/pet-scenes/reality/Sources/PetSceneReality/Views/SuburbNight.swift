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

  static let roadway = ViewRoad(line: road + 1.6, kerb: streetBase, cars: cars)
  static let lamp = ViewStreetLamp(head: lampHead, ground: streetBase, shines: porches.map(\.x))
  static let porches = [CGPoint(x: 15, y: 40.4), CGPoint(x: 75.6, y: 40)]
  static let fairyLights = ViewLightString(
    from: CGPoint(x: 60.5, y: streetBase - 14.4), to: CGPoint(x: 83.5, y: streetBase - 14.4))
  static let roofCatWalk = ViewRoofCat(
    rhythm: roofCat, left: roofPath.left, ridge: roofPath.ridge, right: roofPath.right)

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: farLife(context, moment: moment)
    case .middle:
      ViewWindows.draw(Self.middleWindows, context, moment: moment)
      Self.roofCatWalk.draw(context, moment: moment)
    case .street: streetLife(context, moment: moment)
    case .near: ViewBranch().draw(context, moment: moment)
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

  private func streetLife(_ context: GraphicsContext, moment: ViewMoment) {
    let lamps = moment.lamps
    ViewWindows.draw(Self.streetWindows, context, moment: moment)
    // Porch lights by the doors, always on at night.
    for porch in Self.porches {
      ViewKit.circle(context, porch, 0.4, ViewPalette.lampCore, lamps)
      ViewKit.glow(context, porch, 3.4, ViewPalette.lamp, 0.4 * lamps)
    }
    Self.fairyLights.draw(context, moment: moment)
    Self.lamp.draw(context, moment: moment)
    Self.roadway.draw(context, moment: moment)
  }

  // MARK: - What the cat sees

  func headlight(at now: Double) -> ViewHeadlight? {
    Self.roadway.headlight(at: now)
  }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    Self.roadway.interest(at: moment.now) ?? Self.roofCatWalk.interest(at: moment.now)
  }
}
