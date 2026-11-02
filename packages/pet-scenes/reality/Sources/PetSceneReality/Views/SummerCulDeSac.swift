import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// View 4: a summer cul-de-sac. Far: a line of big round treetops. Middle: houses around the
/// bulb of the street. Street: a lawn with a sprinkler, a trampoline, a basketball hoop over the
/// garage, bikes on the grass, a big oak, a porch with a swing. Near: a hydrangea and a leafy
/// branch. Fireflies come out from dusk, and a bat flits over the street at dusk.
struct SummerCulDeSac: ViewRecipe {
  static let streetBase: CGFloat = 48
  static let roadway = ViewRoad(
    line: 53.4, kerb: streetBase, cars: ViewRhythm(seed: 421, slot: 40, chance: 0.5, length: 6...8),
    length: 12)
  static let lamp = ViewStreetLamp(head: CGPoint(x: 18, y: 15), ground: streetBase)
  static let sprinkler = CGPoint(x: 34, y: 47)
  static let bat = ViewRhythm(seed: 431, slot: 30, chance: 0.6, length: 5...8)

  var moon: CGPoint { CGPoint(x: 64, y: -12) }
  var livePlanes: Set<ViewPlane> { [.middle, .street, .near] }

  func paint(_ plane: ViewPlane, _ context: GraphicsContext, look: ViewLook) {
    let colour = look.palette.colour(plane)
    switch plane {
    case .far:
      ViewKit.ground(context, top: 34, colour: colour)
      for index in 0..<22 {
        let x = -42 + CGFloat(index) * 8.6
        let size = 8 + 6 * CGFloat(ViewRhythm.hash(index, seed: 401))
        ViewKit.tree(
          context, x: x, base: 35, size: size, colour: colour.lit(index % 2 == 0 ? 0.03 : -0.02),
          seed: 40 + index, look: look)
      }
    case .middle: paintMiddle(context, colour: colour, look: look)
    case .street: paintStreet(context, colour: colour, look: look)
    case .near: paintNear(context, colour: colour, look: look)
    }
  }

  static let middleHouses: [(x: CGFloat, width: CGFloat, wall: CGFloat, roof: CGFloat)] = [
    (-30, 22, 9, 6), (-2, 20, 9.5, 6.6), (24, 22, 8.6, 6), (52, 20, 9.2, 6.4), (78, 24, 9, 6.6),
    (108, 22, 9.4, 6.2),
  ]
  static let middleBase: CGFloat = 40

  static let middleWindows: [ViewLitWindow] = middleHouses.enumerated().flatMap { index, house in
    [0.2, 0.62].enumerated().map { slot, share in
      ViewLitWindow(
        id: 500 + index * 2 + slot,
        rect: CGRect(
          x: house.x + house.width * share, y: middleBase - house.wall + 2, width: 2.4, height: 2.8),
        plane: .middle)
    }
  }

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    for (index, house) in Self.middleHouses.enumerated() {
      ViewKit.house(
        context, x: house.x, base: Self.middleBase, width: house.width, wall: house.wall,
        roof: house.roof, colour: colour.lit(index % 2 == 0 ? 0.03 : -0.02), look: look)
    }
    for window in Self.middleWindows { ViewKit.windowFrame(context, window.rect, colour) }
    for (index, x) in [-6.0, 20, 49, 75, 104].enumerated() {
      ViewKit.tree(
        context, x: x, base: Self.middleBase, size: 8, colour: colour.lit(-0.05), seed: 60 + index,
        look: look)
    }
    ViewKit.ground(context, top: Self.middleBase, colour: colour.lit(-0.04))
    // The bulb of the cul-de-sac: a wide pale curve of road in front of the houses.
    context.fill(
      Path(ellipseIn: CGRect(x: -20, y: Self.middleBase - 0.4, width: 140, height: 5)),
      with: .color(colour.lit(look.isDark ? 0.04 : 0.1).color()))
  }

  static let house = (x: CGFloat(56), width: CGFloat(26), wall: CGFloat(14), roof: CGFloat(9))

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let base = Self.streetBase
    let lawn = colour.mixed(with: ViewColour(0x2E5A3A), by: look.isDark ? 0.15 : 0.35)
    ViewKit.ground(context, top: base - 2, colour: lawn)
    // The big oak on the left.
    ViewKit.tree(
      context, x: 6, base: base - 1, size: 22, colour: colour.lit(-0.06), seed: 77, look: look)
    // The house with its porch and swing, and the garage with a hoop.
    let house = Self.house
    ViewKit.house(
      context, x: house.x, base: base, width: house.width, wall: house.wall, roof: house.roof,
      colour: colour.lit(0.03), look: look)
    ViewKit.rect(
      context, CGRect(x: house.x - 1, y: base - 6.6, width: 14, height: 0.8), colour.lit(-0.1))
    for x in [house.x - 0.6, house.x + 12] {
      ViewKit.rect(context, CGRect(x: x, y: base - 6, width: 0.6, height: 6), colour.lit(-0.1))
    }
    for window in Self.streetWindows { ViewKit.windowFrame(context, window.rect, colour) }
    ViewKit.rect(
      context, CGRect(x: house.x + 15, y: base - 7, width: 3, height: 7), colour.lit(-0.3))
    let garage = CGRect(x: house.x + house.width, y: base - 10, width: 13, height: 10)
    ViewKit.rect(context, garage, colour.lit(0.01))
    ViewKit.rect(
      context, garage.insetBy(dx: 1, dy: 1.4).offsetBy(dx: 0, dy: 1.4),
      colour.lit(look.isDark ? 0.07 : 0.13))
    // The hoop: backboard, rim and net.
    ViewKit.rect(
      context, CGRect(x: garage.midX - 2.4, y: garage.minY - 3.6, width: 4.8, height: 3.2),
      ViewColour(0xEEF2F7).mixed(with: colour, by: look.isDark ? 0.6 : 0.2))
    context.stroke(
      Path(ellipseIn: CGRect(x: garage.midX - 1.2, y: garage.minY - 0.7, width: 2.4, height: 0.6)),
      with: .color(ViewColour(0xE5503A).color(look.isDark ? 0.6 : 0.9)), lineWidth: 0.25)
    // A trampoline on the lawn: a dark disc on bowed legs with its net.
    let trampoline = CGPoint(x: 40, y: base - 2.6)
    context.fill(
      Path(ellipseIn: CGRect(x: trampoline.x - 7, y: trampoline.y - 1, width: 14, height: 2)),
      with: .color(colour.lit(-0.25).color()))
    for dx in [-6.0, -2, 2, 6] as [CGFloat] {
      ViewKit.rect(
        context, CGRect(x: trampoline.x + dx, y: trampoline.y, width: 0.4, height: 2.4),
        colour.lit(-0.2))
      ViewKit.rect(
        context, CGRect(x: trampoline.x + dx, y: trampoline.y - 7, width: 0.25, height: 7),
        colour.lit(-0.2))
    }
    var net = Path()
    var nx = trampoline.x - 6
    while nx <= trampoline.x + 6 {
      net.move(to: CGPoint(x: nx, y: trampoline.y - 7))
      net.addLine(to: CGPoint(x: nx, y: trampoline.y - 0.6))
      nx += 0.8
    }
    context.stroke(net, with: .color(colour.lit(0.12).color(0.35)), lineWidth: 0.1)
    ViewKit.rect(
      context, CGRect(x: trampoline.x - 6.2, y: trampoline.y - 7.2, width: 12.4, height: 0.4),
      colour.lit(0.1))
    // Two bikes lying in the grass.
    for (x, tilt) in [(22.0, 0.2), (27, -0.15)] as [(CGFloat, CGFloat)] {
      var bike = context
      bike.translateBy(x: x, y: base - 0.8)
      bike.rotate(by: .radians(Double(tilt)))
      for wheel in [-1.4, 1.4] as [CGFloat] {
        bike.stroke(
          Path(ellipseIn: CGRect(x: wheel - 1, y: -1, width: 2, height: 2)),
          with: .color(colour.lit(-0.3).color()), lineWidth: 0.2)
      }
      var frame = Path()
      frame.move(to: CGPoint(x: -1.4, y: 0))
      frame.addLine(to: CGPoint(x: 0, y: -1.2))
      frame.addLine(to: CGPoint(x: 1.4, y: 0))
      bike.stroke(
        frame,
        with: .color(
          ViewColour(x == 22 ? 0x5BA8FF : 0xFF5FA2).mixed(with: colour, by: 0.5).color()),
        lineWidth: 0.25)
    }
    ViewKit.rect(
      context, CGRect(x: -45, y: base, width: 190, height: 1.4),
      colour.lit(look.isDark ? 0.05 : 0.15))
    ViewKit.ground(context, top: base + 1.4, colour: colour.lit(-0.2))
    ViewKit.streetLampPost(
      context, x: Self.lamp.head.x + 5, top: Self.lamp.head.y - 0.6, base: base + 1.2,
      colour: colour.lit(-0.25))
  }

  static let streetWindows: [ViewLitWindow] = [
    ViewLitWindow(id: 61, rect: CGRect(x: 60, y: 38.6, width: 4.2, height: 4.6), plane: .street),
    ViewLitWindow(id: 62, rect: CGRect(x: 74, y: 38.6, width: 4.2, height: 4.6), plane: .street),
    ViewLitWindow(id: 63, rect: CGRect(x: 67.4, y: 28.6, width: 3.4, height: 3.4), plane: .street),
  ]

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    // A hydrangea along the bottom: clumps of round flower heads among leaves.
    for index in 0..<10 {
      let x = -10 + CGFloat(index) * 7
      let y = 58 - CGFloat(ViewRhythm.hash(index, seed: 411)) * 2.4
      ViewKit.circle(context, CGPoint(x: x, y: y), 5, colour)
      let bloom = ViewColour(index % 3 == 0 ? 0x9AA8FF : 0xC8A0E8).mixed(
        with: colour, by: look.isDark ? 0.7 : 0.35)
      ViewKit.circle(context, CGPoint(x: x + 1.2, y: y - 2.4), 1.8, bloom)
    }
    ViewKit.ground(context, top: 58, colour: colour)
  }

  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: break
    case .middle:
      ViewWindows.draw(Self.middleWindows, context, moment: moment)
      flittingBat(context, moment: moment)
    case .street:
      ViewWindows.draw(Self.streetWindows, context, moment: moment)
      swing(context, moment: moment)
      let porch = CGPoint(x: Self.house.x + 13.5, y: Self.streetBase - 8)
      ViewKit.circle(context, porch, 0.4, ViewPalette.lampCore, moment.lamps)
      ViewKit.glow(context, porch, 5, ViewPalette.lamp, 0.5 * moment.lamps)
      sprinkle(context, moment: moment)
      Self.lamp.draw(context, moment: moment)
      Self.roadway.draw(context, moment: moment)
      ViewFireflies(count: 30, area: CGRect(x: -5, y: 26, width: 110, height: 22))
        .draw(context, moment: moment)
      ViewLeaves(count: 3, area: CGRect(x: -10, y: 10, width: 120, height: 40), seed: 4)
        .draw(context, moment: moment)
    case .near:
      ViewBranch(anchor: CGPoint(x: -16, y: -10), scale: 1.4, side: -1, tint: ViewColour(0x3F8A4E))
        .draw(context, moment: moment)
      ViewFireflies(count: 8, area: CGRect(x: 0, y: 30, width: 100, height: 22), seed: 1)
        .draw(context, moment: moment)
    }
  }

  /// The porch swing, rocking.
  private func swing(_ context: GraphicsContext, moment: ViewMoment) {
    let colour = moment.palette.street.lit(-0.2)
    let angle = sin(moment.now * 1.1) * 4
    var seat = context
    seat.translateBy(x: Self.house.x + 6, y: Self.streetBase - 5.8)
    seat.rotate(by: .degrees(angle))
    for x in [-2.0, 2] as [CGFloat] {
      seat.fill(Path(CGRect(x: x, y: 0, width: 0.12, height: 2.6)), with: .color(colour.color()))
    }
    seat.fill(Path(CGRect(x: -2.4, y: 2.6, width: 4.8, height: 0.7)), with: .color(colour.color()))
  }

  /// A sprinkler throwing an arc of drops back and forth across the lawn.
  private func sprinkle(_ context: GraphicsContext, moment: ViewMoment) {
    let base = Self.sprinkler
    let sweep = sin(moment.now * 0.6) * 0.8
    let colour = moment.palette.skyMiddle.lit(0.55)
    for index in 0..<26 {
      let p = (moment.now * 0.9 + Double(index) / 26).truncatingRemainder(dividingBy: 1)
      let angle = -Double.pi / 2 + sweep + (ViewRhythm.hash(index, seed: 441) - 0.5) * 0.25
      let speed = 9 + 2 * ViewRhythm.hash(index, seed: 442)
      let x = base.x + CGFloat(cos(angle) * speed * p * 1.6)
      let y = base.y + CGFloat(sin(angle) * speed * p + 9 * p * p)
      ViewKit.circle(context, CGPoint(x: x, y: y), 0.18, colour, 0.6 * (1 - p))
    }
    if moment.lamps > 0 {
      ViewKit.glow(
        context, CGPoint(x: base.x, y: base.y - 3), 4, ViewPalette.lamp, 0.06 * moment.lamps)
    }
  }

  /// A bat at dusk: a quick zigzag across the street.
  private func flittingBat(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.hour == .dusk || moment.look.hour == .night,
      let pass = Self.bat.pass(at: moment.now)
    else { return }
    let point = Self.batPoint(pass, now: moment.now)
    let flap = sin(moment.now * 28)
    var wings = Path()
    wings.move(to: CGPoint(x: point.x - 1.4, y: point.y - CGFloat(flap) * 0.8))
    wings.addLine(to: point)
    wings.addLine(to: CGPoint(x: point.x + 1.4, y: point.y - CGFloat(flap) * 0.8))
    context.stroke(wings, with: .color(moment.palette.near.color()), lineWidth: 0.35)
  }

  static func batPoint(_ pass: ViewRhythm.Pass, now: Double) -> CGPoint {
    let p = pass.progress
    let x = pass.variant < 0.5 ? -10 + 120 * p : 110 - 120 * p
    return CGPoint(x: x, y: 14 + 6 * sin(p * 9 + pass.variant * 6) + 2 * sin(now * 3))
  }

  func headlight(at now: Double) -> ViewHeadlight? { Self.roadway.headlight(at: now) }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if let car = Self.roadway.interest(at: moment.now) { return car }
    if moment.look.hour == .dusk || moment.look.hour == .night,
      let pass = Self.bat.pass(at: moment.now)
    {
      let point = Self.batPoint(pass, now: moment.now)
      if point.x > 0, point.x < 100 {
        return ViewInterest(point: point, plane: .middle, paw: false, id: pass.index)
      }
    }
    return nil
  }
}
