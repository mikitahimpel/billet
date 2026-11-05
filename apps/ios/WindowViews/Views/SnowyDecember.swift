import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// View 3: a snowy December street. Far: white hills with the town's big tree lit on top. Middle:
/// houses with lights along their gutters and smoke from the chimneys. Street: one house that
/// went all out (lights on every edge, an inflatable snowman, a lit tree in the yard) beside a
/// neighbour with a single warm string; a snowman someone built. Near: icicles along the eave
/// above the window and a snowy fence.
struct SnowyDecember: ViewRecipe {
  static let streetBase: CGFloat = 48
  static let roadway = ViewRoad(
    line: 53.4, kerb: streetBase,
    cars: ViewRhythm(seed: 321, slot: 24, chance: 0.6, length: 4.4...6.4))
  static let lamp = ViewStreetLamp(head: CGPoint(x: 12, y: 14), ground: streetBase)
  static let townTree = CGPoint(x: 86, y: 18)

  var moon: CGPoint { CGPoint(x: 30, y: -18) }
  var livePlanes: Set<ViewPlane> { [.far, .middle, .street, .near] }

  func paint(_ plane: ViewPlane, _ context: GraphicsContext, look: ViewLook) {
    let colour = look.palette.colour(plane)
    let snow = ViewKit.snow(look)
    switch plane {
    case .far:
      ViewKit.hills(
        context, base: 35, waves: [5, 3, 6, 4, 7, 3, 5, 4],
        colour: snow.mixed(with: colour, by: 0.55))
      ViewKit.ground(context, top: 35, colour: snow.mixed(with: colour, by: 0.6))
      for index in 0..<16 {
        let x = -40 + CGFloat(index) * 12 + CGFloat(ViewRhythm.hash(index, seed: 301)) * 6
        ViewKit.pine(
          context, x: x, base: 35.5, height: 5 + 3 * CGFloat(ViewRhythm.hash(index, seed: 302)),
          colour: colour.lit(-0.1), look: look)
      }
      ViewKit.pine(
        context, x: Self.townTree.x, base: 35, height: 17, colour: colour.lit(-0.15), look: look)
    case .middle: paintMiddle(context, colour: colour, look: look)
    case .street: paintStreet(context, colour: colour, look: look)
    case .near: paintNear(context, colour: colour, look: look)
    }
  }

  static let middleHouses: [(x: CGFloat, width: CGFloat, wall: CGFloat, roof: CGFloat)] = [
    (-36, 18, 8, 6), (-12, 17, 9, 7), (10, 20, 8, 6), (34, 18, 9, 7), (58, 19, 8.4, 6.4),
    (82, 20, 9, 7), (106, 18, 8, 6.2), (128, 17, 9, 6.6),
  ]
  static let middleBase: CGFloat = 40

  static let middleWindows: [ViewLitWindow] = middleHouses.enumerated().flatMap { index, house in
    [0.22, 0.64].enumerated().map { slot, share in
      ViewLitWindow(
        id: 400 + index * 2 + slot,
        rect: CGRect(
          x: house.x + house.width * share, y: middleBase - house.wall + 2, width: 2.2, height: 2.6),
        plane: .middle)
    }
  }

  static let chimneys: [CGPoint] = middleHouses.enumerated().compactMap { index, house in
    index % 2 == 0
      ? CGPoint(x: house.x + house.width * 0.72, y: middleBase - house.wall - house.roof * 0.75)
      : nil
  }

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    for (index, x) in [-22.0, 6, 30, 77, 102].enumerated() {
      ViewKit.pine(
        context, x: x, base: Self.middleBase, height: 14, colour: colour.lit(-0.06), look: look)
      _ = index
    }
    for (index, house) in Self.middleHouses.enumerated() {
      if index % 2 == 0 {
        ViewKit.rect(
          context,
          CGRect(
            x: house.x + house.width * 0.68, y: Self.middleBase - house.wall - house.roof * 0.75,
            width: 1.6, height: house.roof), colour.lit(-0.1))
      }
      ViewKit.house(
        context, x: house.x, base: Self.middleBase, width: house.width, wall: house.wall,
        roof: house.roof, colour: colour.lit(index % 2 == 0 ? 0.03 : -0.02), look: look)
    }
    for window in Self.middleWindows { ViewKit.windowFrame(context, window.rect, colour) }
    ViewKit.ground(
      context, top: Self.middleBase, colour: ViewKit.snow(look).mixed(with: colour, by: 0.4))
  }

  /// The big house's outline, where its lights run: eaves, gable and corners.
  static let bigHouse = (x: CGFloat(54), width: CGFloat(30), wall: CGFloat(14), roof: CGFloat(10))
  static let neighbour = (
    x: CGFloat(-20), width: CGFloat(28), wall: CGFloat(13), roof: CGFloat(8.5)
  )

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let base = Self.streetBase
    let snow = ViewKit.snow(look)
    ViewKit.ground(context, top: base - 1, colour: snow.mixed(with: colour, by: 0.25))
    let big = Self.bigHouse
    ViewKit.house(
      context, x: big.x, base: base, width: big.width, wall: big.wall, roof: big.roof,
      colour: colour.lit(0.03), look: look)
    let next = Self.neighbour
    ViewKit.house(
      context, x: next.x, base: base, width: next.width, wall: next.wall, roof: next.roof,
      colour: colour.lit(0.02), look: look)
    for window in Self.streetWindows { ViewKit.windowFrame(context, window.rect, colour) }
    // Doors, the big house's with a wreath drawn by the life.
    ViewKit.rect(context, CGRect(x: 67.5, y: base - 7, width: 3, height: 7), colour.lit(-0.3))
    ViewKit.rect(context, CGRect(x: -2, y: base - 6.6, width: 3, height: 6.6), colour.lit(-0.3))
    // A snowman someone built: three balls, a stick arm, a scarf.
    let man = CGPoint(x: 26, y: base - 0.4)
    for (rise, r) in [(2.2, 2.4), (5.6, 1.7), (8.2, 1.2)] as [(CGFloat, CGFloat)] {
      ViewKit.circle(context, CGPoint(x: man.x, y: man.y - rise), r, snow)
    }
    var arm = Path()
    arm.move(to: CGPoint(x: man.x + 1.4, y: man.y - 5.8))
    arm.addLine(to: CGPoint(x: man.x + 3.6, y: man.y - 7.4))
    context.stroke(arm, with: .color(colour.lit(-0.3).color()), lineWidth: 0.3)
    ViewKit.rect(
      context, CGRect(x: man.x - 1.2, y: man.y - 7.3, width: 2.4, height: 0.6),
      ViewColour(0xE5503A), look.isDark ? 0.6 : 0.9)
    // A car in the driveway with snow on its roof.
    ViewKit.car(context, x: 30, base: base, length: 12, body: colour.lit(-0.1))
    ViewKit.rect(context, CGRect(x: 30, y: base - 4.3, width: 12, height: 0.6), snow, 0.9)
    // Sidewalk, road and banks of plowed snow.
    ViewKit.rect(
      context, CGRect(x: -45, y: base, width: 190, height: 1.4), snow.mixed(with: colour, by: 0.3))
    ViewKit.ground(context, top: base + 1.4, colour: colour.lit(-0.15).mixed(with: snow, by: 0.35))
    for index in 0..<12 {
      let x = -40 + CGFloat(index) * 16
      context.fill(
        Path(ellipseIn: CGRect(x: x, y: base + 0.2, width: 9, height: 2.2)),
        with: .color(snow.color()))
    }
    ViewKit.streetLampPost(
      context, x: Self.lamp.head.x + 5, top: Self.lamp.head.y - 0.6, base: base + 1.2,
      colour: colour.lit(-0.25))
  }

  static let streetWindows: [ViewLitWindow] = [
    ViewLitWindow(id: 51, rect: CGRect(x: -14, y: 38.6, width: 4, height: 4.4), plane: .street),
    ViewLitWindow(id: 52, rect: CGRect(x: 4, y: 38.6, width: 4, height: 4.4), plane: .street),
    ViewLitWindow(id: 53, rect: CGRect(x: 58, y: 38, width: 4.4, height: 5), plane: .street),
    ViewLitWindow(id: 54, rect: CGRect(x: 75.6, y: 38, width: 4.4, height: 5), plane: .street),
    ViewLitWindow(id: 55, rect: CGRect(x: 67.2, y: 27.6, width: 3.6, height: 3.6), plane: .street),
  ]

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    // The eave above the window, heavy with snow, and a fence below.
    ViewKit.rect(context, CGRect(x: -45, y: -50, width: 190, height: 49), colour)
    context.fill(
      Path(roundedRect: CGRect(x: -45, y: -2.4, width: 190, height: 3.2), cornerRadius: 1.6),
      with: .color(ViewKit.snow(look).color()))
    ViewKit.fence(context, from: -44, to: 145, base: 60, height: 9, colour: colour, look: look)
  }

  // MARK: - Life

  static let gutterLights: [ViewLightString] = {
    let big = bigHouse
    let eave = streetBase - big.wall
    let ridge = CGPoint(x: big.x + big.width / 2, y: eave - big.roof)
    let left = CGPoint(x: big.x - 1.2, y: eave + 0.4)
    let right = CGPoint(x: big.x + big.width + 1.2, y: eave + 0.4)
    let next = neighbour
    let nextEave = streetBase - next.wall
    var strings = [
      ViewLightString(
        from: left, to: ridge, sag: 0.2, count: 14, colours: ViewLightString.christmas,
        chases: true, seed: 0),
      ViewLightString(
        from: ridge, to: right, sag: 0.2, count: 14, colours: ViewLightString.christmas,
        chases: true, seed: 3),
      ViewLightString(
        from: CGPoint(x: big.x, y: eave + 0.6), to: CGPoint(x: big.x + big.width, y: eave + 0.6),
        sag: 0.8, count: 18, colours: ViewLightString.christmas, chases: true, seed: 5),
      ViewLightString(
        from: CGPoint(x: next.x - 1, y: nextEave + 0.5),
        to: CGPoint(x: next.x + next.width + 1, y: nextEave + 0.5), sag: 0.9, count: 16, seed: 2),
    ]
    for (index, house) in middleHouses.enumerated() where index % 3 != 1 {
      let eave = middleBase - house.wall + 0.4
      strings.append(
        ViewLightString(
          from: CGPoint(x: house.x, y: eave), to: CGPoint(x: house.x + house.width, y: eave),
          sag: 0.5,
          count: 9, colours: index % 2 == 0 ? ViewLightString.christmas : [ViewPalette.lampCore],
          seed: index))
    }
    return strings
  }()

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: townTree(context, moment: moment)
    case .middle:
      ViewWindows.draw(Self.middleWindows, context, moment: moment)
      for string in Self.gutterLights.dropFirst(4) { string.draw(context, moment: moment) }
      smoke(context, moment: moment)
    case .street: streetLife(context, moment: moment)
    case .near: icicles(context, moment: moment)
    }
  }

  private func townTree(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.lamps > 0 else { return }
    let tree = Self.townTree
    for index in 0..<16 {
      let row = CGFloat(index / 4)
      let x = tree.x + (CGFloat(index % 4) - 1.5) * (1.2 + row * 0.6)
      let y = tree.y + 2 + row * 3.4
      let twinkle = 0.6 + 0.4 * sin(moment.now * 2 + Double(index) * 1.7)
      let colour = ViewLightString.christmas[index % 5]
      ViewKit.glow(context, CGPoint(x: x, y: y), 0.9, colour, twinkle * moment.lamps)
    }
    ViewKit.glow(
      context, CGPoint(x: tree.x, y: tree.y - 0.6), 1.8, ViewColour(0xFFD166), moment.lamps)
  }

  /// Smoke curling up from the chimneys, drifting with the wind.
  private func smoke(_ context: GraphicsContext, moment: ViewMoment) {
    let colour = moment.palette.skyMiddle.lit(moment.look.isDark ? 0.15 : 0.35)
    for (index, top) in Self.chimneys.enumerated() {
      for puff in 0..<6 {
        let p = (moment.now * 0.12 + Double(puff) / 6 + ViewRhythm.hash(index, seed: 311))
          .truncatingRemainder(dividingBy: 1)
        let rise = CGFloat(p) * 16
        let drift = CGFloat(p * p) * 9 + CGFloat(sin(moment.now * 0.5 + Double(puff))) * 0.8
        ViewKit.circle(
          context, CGPoint(x: top.x + 0.8 + drift, y: top.y - rise), 0.8 + CGFloat(p) * 2.2, colour,
          0.28 * (1 - p))
      }
    }
  }

  /// A neighbour clearing the driveway now and then: scoop, lift, toss, a puff of snow.
  static let shoveller = ViewRhythm(seed: 351, slot: 90, chance: 0.6, length: 50...80)
  static let shovelSpot = CGPoint(x: 46, y: streetBase + 0.2)

  private func shovelling(_ context: GraphicsContext, moment: ViewMoment) {
    guard Self.shoveller.pass(at: moment.now) != nil else { return }
    let spot = Self.shovelSpot
    ViewWalker.figure(
      context, at: spot, height: 6.4, facing: -1, kind: .walker, coat: 0xE5503A, plane: .street,
      moment: moment, walking: false)
    // One stroke every 2.4 s: down to the snow, up and over the shoulder.
    let phase = (moment.now / 2.4).truncatingRemainder(dividingBy: 1)
    let lift = phase < 0.5 ? 0 : sin((phase - 0.5) / 0.5 * Double.pi)
    let angle = -0.35 - 1.2 * lift
    let hands = CGPoint(x: spot.x - 0.6, y: spot.y - 3.6)
    let blade = CGPoint(
      x: hands.x - 3.6 * CGFloat(cos(angle)), y: hands.y - 3.6 * CGFloat(sin(angle)))
    var shaft = Path()
    shaft.move(to: hands)
    shaft.addLine(to: blade)
    let dark = moment.palette.street.lit(-0.4)
    context.stroke(shaft, with: .color(dark.color()), lineWidth: 0.22)
    ViewKit.rect(context, CGRect(x: blade.x - 0.7, y: blade.y - 0.3, width: 1.4, height: 0.6), dark)
    // The toss: a puff of snow flying off the blade and falling.
    if phase > 0.7 {
      let t = (phase - 0.7) / 0.3
      let snow = ViewKit.snow(moment.look)
      for flake in 0..<6 {
        let spread = CGFloat(ViewRhythm.hash(flake, seed: 352))
        let x = blade.x - CGFloat(t) * (3 + 3 * spread)
        let y = blade.y - CGFloat(sin(t * Double.pi)) * (2 + spread) + CGFloat(t * t) * 3
        ViewKit.circle(context, CGPoint(x: x, y: y), 0.25 + 0.2 * spread, snow, 0.9 * (1 - t))
      }
    }
  }

  private func streetLife(_ context: GraphicsContext, moment: ViewMoment) {
    ViewWindows.draw(Self.streetWindows, context, moment: moment)
    shovelling(context, moment: moment)
    for string in Self.gutterLights.prefix(4) { string.draw(context, moment: moment) }
    let lamps = moment.lamps
    // The wreath on the big house's door, with a red bow.
    let wreath = CGPoint(x: 69, y: Self.streetBase - 4.6)
    context.stroke(
      Path(ellipseIn: CGRect(x: wreath.x - 1, y: wreath.y - 1, width: 2, height: 2)),
      with: .color(ViewColour(0x2E6B4A).color()), lineWidth: 0.6)
    ViewKit.circle(context, CGPoint(x: wreath.x, y: wreath.y + 1), 0.35, ViewColour(0xE5503A))
    // The inflatable snowman, glowing from inside and bobbing a little in the wind.
    let bob = CGFloat(sin(moment.now * 0.8)) * 0.3
    let body = ViewColour(0xF6F8FF).mixed(
      with: moment.palette.street, by: moment.look.isDark ? 0.45 - 0.3 * lamps : 0.1)
    let man = CGPoint(x: 90 + bob, y: Self.streetBase - 0.2)
    ViewKit.circle(context, CGPoint(x: man.x, y: man.y - 3.4), 3.4, body)
    ViewKit.circle(context, CGPoint(x: man.x, y: man.y - 8.6), 2.4, body)
    ViewKit.rect(
      context, CGRect(x: man.x - 1.6, y: man.y - 12.6, width: 3.2, height: 1.8),
      ViewColour(0x1A1A22))
    ViewKit.rect(
      context, CGRect(x: man.x - 2.4, y: man.y - 11, width: 4.8, height: 0.5), ViewColour(0x1A1A22))
    ViewKit.rect(
      context, CGRect(x: man.x - 2, y: man.y - 6.6, width: 4, height: 0.8), ViewColour(0xE5503A))
    ViewKit.glow(context, CGPoint(x: man.x, y: man.y - 5), 7, ViewColour(0xDDE6FF), 0.25 * lamps)
    // A lit tree in the yard.
    let tree = CGPoint(x: 46, y: Self.streetBase - 0.4)
    ViewKit.pine(
      context, x: tree.x, base: tree.y, height: 12, colour: moment.palette.street.lit(-0.1),
      look: moment.look)
    if lamps > 0 {
      for index in 0..<14 {
        let row = CGFloat(index / 4)
        let x = tree.x + (CGFloat(index % 4) - 1.5) * (0.8 + row * 0.5)
        let y = tree.y - 9.6 + row * 2.6
        let twinkle = 0.55 + 0.45 * sin(moment.now * 2.6 + Double(index) * 2.1)
        ViewKit.glow(
          context, CGPoint(x: x, y: y), 0.9, ViewLightString.christmas[(index + 2) % 5],
          twinkle * lamps)
      }
      ViewKit.glow(context, CGPoint(x: tree.x, y: tree.y - 12), 1.4, ViewColour(0xFFD166), lamps)
    }
    Self.lamp.draw(context, moment: moment)
    Self.roadway.draw(context, moment: moment)
  }

  /// Icicles along the eave, each with a glint now and then and a drop forming at its tip.
  private func icicles(_ context: GraphicsContext, moment: ViewMoment) {
    let ice = ViewColour(0xDDEBFF).mixed(
      with: moment.palette.skyMiddle, by: moment.look.isDark ? 0.4 : 0.1)
    for index in 0..<26 {
      let x = -6 + CGFloat(index) * 4.4 + CGFloat(ViewRhythm.hash(index, seed: 321)) * 2
      let length = 2 + 5 * CGFloat(ViewRhythm.hash(index, seed: 322))
      var spike = Path()
      spike.move(to: CGPoint(x: x - 0.5, y: 0.6))
      spike.addLine(to: CGPoint(x: x, y: 0.6 + length))
      spike.addLine(to: CGPoint(x: x + 0.5, y: 0.6))
      spike.closeSubpath()
      context.fill(spike, with: .color(ice.color(0.85)))
      let glint = sin(moment.now * 0.7 + Double(index) * 2.3)
      if glint > 0.96 {
        ViewKit.glow(
          context, CGPoint(x: x, y: length * 0.5), 1.2, ViewColour(0xFFFFFF), (glint - 0.96) * 20)
      }
    }
  }

  func headlight(at now: Double) -> ViewHeadlight? { Self.roadway.headlight(at: now) }

  func interest(at moment: ViewMoment) -> ViewInterest? { Self.roadway.interest(at: moment.now) }
}
