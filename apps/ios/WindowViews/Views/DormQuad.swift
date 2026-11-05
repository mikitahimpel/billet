import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// View 5: a college quad from a dorm room. Far: other halls and the clock tower, whose hands
/// keep the real time. Middle: the brick dorm across the quad, its windows lit every way students
/// light them: lamps, a TV, LED strips slowly changing colour, fairy lights. Street: the lawn
/// with paths cutting across it, globe lamps, benches and a bike rack. Near: a clipped hedge.
/// People cross the paths with backpacks and phones; by day a frisbee goes back and forth and a
/// squirrel dashes over the grass.
struct DormQuad: ViewRecipe {
  static let lawn: CGFloat = 42
  static let tower = CGPoint(x: 76, y: 15)
  static let globes = [CGPoint(x: 20, y: 34.6), CGPoint(x: 58, y: 34.6), CGPoint(x: 98, y: 34.6)]
  static let walkers = [
    ViewWalker(
      rhythm: ViewRhythm(seed: 501, slot: 26, chance: 0.75, length: 14...20),
      from: CGPoint(x: -20, y: 44), to: CGPoint(x: 120, y: 50.5), height: 6,
      kinds: [.backpack, .phone, .backpack, .walker]),
    ViewWalker(
      rhythm: ViewRhythm(seed: 502, slot: 34, chance: 0.6, length: 16...22),
      from: CGPoint(x: -20, y: 50), to: CGPoint(x: 120, y: 44.5), height: 6,
      kinds: [.phone, .backpack, .skater]),
  ]
  static let frisbee = ViewRhythm(seed: 511, slot: 9, chance: 0.85, length: 2.2...3)
  static let squirrel = ViewRhythm(seed: 521, slot: 40, chance: 0.5, length: 3...4.5)

  var moon: CGPoint { CGPoint(x: 40, y: -14) }
  var livePlanes: Set<ViewPlane> { [.far, .middle, .street] }

  func paint(_ plane: ViewPlane, _ context: GraphicsContext, look: ViewLook) {
    let colour = look.palette.colour(plane)
    switch plane {
    case .far: paintFar(context, colour: colour, look: look)
    case .middle: paintMiddle(context, colour: colour, look: look)
    case .street: paintStreet(context, colour: colour, look: look)
    case .near: paintNear(context, colour: colour, look: look)
    }
  }

  // MARK: - Far: halls and the clock tower

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let base: CGFloat = 37
    for (index, hall) in [(-40.0, 30.0, 8.0), (44, 22, 9), (96, 34, 7.5), (128, 20, 8.6)]
      .enumerated() as EnumeratedSequence<[(CGFloat, CGFloat, CGFloat)]>
    {
      let tone = colour.lit(index % 2 == 0 ? 0.02 : -0.02)
      ViewKit.rect(
        context, CGRect(x: hall.0, y: base - hall.2, width: hall.1, height: hall.2), tone)
      var roof = Path()
      roof.move(to: CGPoint(x: hall.0 - 1, y: base - hall.2))
      roof.addLine(to: CGPoint(x: hall.0 + 3, y: base - hall.2 - 3.4))
      roof.addLine(to: CGPoint(x: hall.0 + hall.1 - 3, y: base - hall.2 - 3.4))
      roof.addLine(to: CGPoint(x: hall.0 + hall.1 + 1, y: base - hall.2))
      roof.closeSubpath()
      context.fill(roof, with: .color(tone.lit(-0.05).color()))
      var x = hall.0 + 2
      while x < hall.0 + hall.1 - 2 {
        let lit =
          look.isDark && ViewRhythm.hash(Int(x * 7), seed: 531) < look.palette.litShare * 0.8
        ViewKit.rect(
          context, CGRect(x: x, y: base - hall.2 + 2, width: 1, height: 1.6),
          lit ? ViewPalette.lamp : tone.lit(-0.12), lit ? 0.7 : 1)
        x += 3
      }
    }
    for (index, x) in [8.0, 22, 36, 60, 92, 114].enumerated() {
      ViewKit.tree(
        context, x: x, base: base, size: 7 + CGFloat(index % 3), colour: colour.lit(-0.04),
        seed: 500 + index, look: look)
    }
    // The clock tower: a square shaft, a belfry with arches, a spire.
    let tower = Self.tower
    let shaft = colour.lit(look.isDark ? 0.04 : 0.06)
    ViewKit.rect(
      context, CGRect(x: tower.x - 4, y: tower.y - 3, width: 8, height: base - tower.y + 3), shaft)
    ViewKit.rect(
      context, CGRect(x: tower.x - 4.6, y: tower.y - 4, width: 9.2, height: 1), shaft.lit(-0.06))
    ViewKit.rect(context, CGRect(x: tower.x - 3.6, y: tower.y - 10, width: 7.2, height: 6), shaft)
    for dx in [-2.0, 0.6] as [CGFloat] {
      context.fill(
        Path(
          roundedRect: CGRect(x: tower.x + dx, y: tower.y - 9, width: 1.4, height: 4),
          cornerRadius: 0.7),
        with: .color(shaft.lit(-0.2).color()))
    }
    var spire = Path()
    spire.move(to: CGPoint(x: tower.x - 4.2, y: tower.y - 10))
    spire.addLine(to: CGPoint(x: tower.x, y: tower.y - 21))
    spire.addLine(to: CGPoint(x: tower.x + 4.2, y: tower.y - 10))
    spire.closeSubpath()
    context.fill(spire, with: .color(shaft.lit(-0.04).color()))
    ViewKit.circle(context, tower, 2.6, shaft.lit(-0.08))
    ViewKit.circle(
      context, tower, 2.2,
      look.isDark
        ? ViewPalette.lampCore.mixed(with: shaft, by: 0.25)
        : ViewColour(0xEEF2F7).mixed(with: shaft, by: 0.3))
    ViewKit.ground(context, top: base, colour: colour.lit(-0.03))
  }

  // MARK: - Middle: the dorm

  static let dorm = CGRect(x: -34, y: 13, width: 86, height: 27)
  static let columns = 13
  static let floors = 4

  static func window(column: Int, floor: Int) -> CGRect {
    CGRect(
      x: dorm.minX + 3 + CGFloat(column) * 6.4, y: dorm.minY + 3 + CGFloat(floor) * 6, width: 3.2,
      height: 3.6)
  }

  /// What lights a dorm window: plain lamps and TVs as the street's windows, and the students'
  /// own lights drawn here.
  enum Glow: Sendable {
    case led(hue: Double)
    case fairy
  }

  static let ledWindows: [(column: Int, floor: Int, glow: Glow)] = [
    (6, 1, .led(hue: 0.78)), (9, 0, .led(hue: 0.9)), (8, 3, .led(hue: 0.5)), (11, 2, .fairy),
    (7, 2, .fairy), (10, 1, .led(hue: 0.62)),
  ]

  static let windows: [ViewLitWindow] = (0..<floors).flatMap { floor in
    (0..<columns).compactMap { column in
      guard !ledWindows.contains(where: { $0.column == column && $0.floor == floor }) else {
        return nil
      }
      return ViewLitWindow(
        id: 700 + floor * 20 + column, rect: window(column: column, floor: floor), plane: .middle,
        isTV: (column * 7 + floor * 3) % 11 == 0)
    }
  }

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let brick = colour.mixed(with: ViewColour(0x9A4A38), by: look.isDark ? 0.22 : 0.4)
    let dorm = Self.dorm
    ViewKit.rect(context, dorm, brick)
    // A stone band between floors and a parapet with a cornice.
    for floor in 1..<Self.floors {
      ViewKit.rect(
        context,
        CGRect(
          x: dorm.minX, y: dorm.minY + 1.6 + CGFloat(floor) * 6, width: dorm.width, height: 0.5),
        brick.lit(0.08))
    }
    ViewKit.rect(
      context, CGRect(x: dorm.minX - 1, y: dorm.minY - 1.2, width: dorm.width + 2, height: 1.4),
      brick.lit(0.1))
    ViewKit.rect(
      context, CGRect(x: dorm.minX + 10, y: dorm.minY - 4, width: 7, height: 3), brick.lit(-0.06))
    for floor in 0..<Self.floors {
      for column in 0..<Self.columns {
        let rect = Self.window(column: column, floor: floor)
        ViewKit.windowFrame(context, rect, brick)
        ViewKit.rect(
          context, CGRect(x: rect.minX - 0.3, y: rect.maxY, width: rect.width + 0.6, height: 0.4),
          brick.lit(0.12))
      }
    }
    // The entrance with its steps, at the dorm's right end.
    let door = CGRect(x: dorm.maxX - 9, y: dorm.maxY - 5, width: 4, height: 5)
    ViewKit.rect(context, door.insetBy(dx: -1, dy: -1).offsetBy(dx: 0, dy: 0.5), brick.lit(0.1))
    ViewKit.rect(context, door, brick.lit(-0.35))
    // A low hall to the right, under the tower.
    ViewKit.rect(context, CGRect(x: 96, y: 30, width: 50, height: 10), colour.lit(-0.02))
    for x in stride(from: 99.0, to: 146, by: 5) {
      ViewKit.windowFrame(context, CGRect(x: x, y: 32.6, width: 2.4, height: 3), colour.lit(-0.02))
    }
    ViewKit.ground(context, top: dorm.maxY, colour: colour.lit(-0.04))
  }

  // MARK: - Street: the quad

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let grass = colour.mixed(with: ViewColour(0x2E5A3A), by: look.isDark ? 0.18 : 0.4)
    ViewKit.ground(context, top: Self.lawn, colour: grass)
    // Paths: a walk along the dorm and two that cut across, worn where people really go.
    let stone = colour.lit(look.isDark ? 0.06 : 0.16)
    ViewKit.rect(context, CGRect(x: -45, y: Self.lawn, width: 190, height: 1.2), stone)
    for walker in Self.walkers {
      var path = Path()
      let dx = walker.to.x - walker.from.x
      let dy = walker.to.y - walker.from.y
      path.move(to: CGPoint(x: walker.from.x - dx * 0.2, y: walker.from.y - dy * 0.2 - 0.8))
      path.addLine(to: CGPoint(x: walker.to.x + dx * 0.2, y: walker.to.y + dy * 0.2 - 0.8))
      path.addLine(to: CGPoint(x: walker.to.x + dx * 0.2, y: walker.to.y + dy * 0.2 + 0.8))
      path.addLine(to: CGPoint(x: walker.from.x - dx * 0.2, y: walker.from.y - dy * 0.2 + 0.8))
      path.closeSubpath()
      context.fill(path, with: .color(stone.color()))
    }
    // A big tree on the lawn.
    ViewKit.tree(
      context, x: 84, base: 45, size: 17, colour: colour.lit(-0.06), seed: 541, look: look)
    // Globe lamp posts.
    for globe in Self.globes {
      ViewKit.rect(
        context, CGRect(x: globe.x - 0.35, y: globe.y + 1, width: 0.7, height: 46 - globe.y),
        colour.lit(-0.25))
      ViewKit.rect(
        context, CGRect(x: globe.x - 0.8, y: 45, width: 1.6, height: 1.2), colour.lit(-0.25))
      ViewKit.circle(
        context, globe, 1.3,
        look.isDark ? colour.lit(0.1) : ViewColour(0xEEF2F7).mixed(with: colour, by: 0.35))
    }
    // Benches, and a rack of bikes.
    for x in [30.0, 66] as [CGFloat] {
      ViewKit.rect(context, CGRect(x: x, y: 44.2, width: 6, height: 0.6), colour.lit(-0.2))
      ViewKit.rect(context, CGRect(x: x, y: 42.4, width: 6, height: 0.5), colour.lit(-0.2))
      for leg in [x + 0.4, x + 5.2] {
        ViewKit.rect(context, CGRect(x: leg, y: 44.8, width: 0.4, height: 1.2), colour.lit(-0.25))
      }
    }
    let bikes: [UInt32] = [0x5BA8FF, 0xE5503A, 0x3DDC84, 0xFFD166]
    for (index, body) in bikes.enumerated() {
      let x = 38 + CGFloat(index) * 2.4
      for wheel in [-1.0, 1.0] as [CGFloat] {
        context.stroke(
          Path(ellipseIn: CGRect(x: x - 0.9, y: 42.4 + wheel * 0.5, width: 1.8, height: 1.8)),
          with: .color(colour.lit(-0.3).color()), lineWidth: 0.18)
      }
      ViewKit.rect(
        context, CGRect(x: x - 0.15, y: 42.4, width: 0.3, height: 2.2),
        ViewColour(body).mixed(with: colour, by: look.isDark ? 0.7 : 0.45))
    }
    ViewKit.rect(context, CGRect(x: 36.6, y: 44, width: 10, height: 0.35), colour.lit(-0.15))
  }

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    // A clipped hedge, flat on top, along the bottom of the window.
    context.fill(
      Path(roundedRect: CGRect(x: -50, y: 52.4, width: 200, height: 20), cornerRadius: 2.4),
      with: .color(colour.color()))
    for index in 0..<26 {
      let x = -44 + CGFloat(index) * 7.4
      ViewKit.circle(
        context, CGPoint(x: x, y: 53.4), 1.6, colour.lit(index % 2 == 0 ? 0.03 : -0.02))
    }
    if look.weather == .snow {
      ViewKit.rect(
        context, CGRect(x: -50, y: 52, width: 200, height: 0.9), ViewKit.snow(look), 0.85)
    }
  }

  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: clock(context, moment: moment)
    case .middle:
      ViewWindows.draw(Self.windows, context, moment: moment)
      studentLights(context, moment: moment)
    case .street:
      for globe in Self.globes {
        ViewKit.circle(context, globe, 1.3, ViewPalette.lampCore, moment.lamps)
        ViewKit.glow(context, globe, 7, ViewPalette.lamp, 0.45 * moment.lamps)
        ViewKit.glow(
          context, CGPoint(x: globe.x, y: 46), 6, ViewPalette.lamp, 0.12 * moment.lamps)
      }
      frisbee(context, moment: moment)
      benchSitter(context, moment: moment)
      squirrel(context, moment: moment)
      for walker in Self.walkers { walker.draw(context, moment: moment) }
      ViewLeaves(count: 4, area: CGRect(x: -10, y: 8, width: 120, height: 42), seed: 5)
        .draw(context, moment: moment)
    case .near: break
    }
  }

  /// The tower clock's hands at the real time here, and its face lit after dark.
  private func clock(_ context: GraphicsContext, moment: ViewMoment) {
    let centre = Self.tower
    ViewKit.glow(context, centre, 6, ViewPalette.lampCore, 0.35 * moment.lamps)
    let parts = Calendar.current.dateComponents(
      [.hour, .minute], from: Date(timeIntervalSinceReferenceDate: moment.now))
    let minutes = Double(parts.minute ?? 0)
    let hours = Double((parts.hour ?? 0) % 12) + minutes / 60
    let ink = moment.palette.far.lit(-0.3)
    for (turn, length, width) in [(hours / 12, 1.1, 0.35), (minutes / 60, 1.8, 0.22)]
      as [(Double, CGFloat, CGFloat)]
    {
      let angle = turn * 2 * Double.pi - Double.pi / 2
      var hand = Path()
      hand.move(to: centre)
      hand.addLine(
        to: CGPoint(
          x: centre.x + CGFloat(cos(angle)) * length, y: centre.y + CGFloat(sin(angle)) * length))
      context.stroke(
        hand, with: .color(ink.color()), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
  }

  /// LED strips that drift slowly through colours, and fairy lights pinned round a window.
  private func studentLights(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.lamps > 0 else { return }
    for (index, light) in Self.ledWindows.enumerated() {
      let rect = Self.window(column: light.column, floor: light.floor)
      switch light.glow {
      case .led(let hue):
        let drift = (hue + moment.now / 90 + 0.08 * sin(moment.now / 7 + Double(index)))
          .truncatingRemainder(dividingBy: 1)
        let colour = ViewColour(hue: drift)
        context.fill(
          Path(rect),
          with: .linearGradient(
            Gradient(colors: [colour.color(0.25 * moment.lamps), colour.color(0.85 * moment.lamps)]
            ),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        ViewKit.rect(
          context, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 0.35),
          colour.lit(0.3), moment.lamps)
        ViewKit.glow(context, CGPoint(x: rect.midX, y: rect.midY), 5, colour, 0.25 * moment.lamps)
      case .fairy:
        ViewKit.rect(context, rect, ViewPalette.lamp, 0.3 * moment.lamps)
        ViewLightString(
          from: CGPoint(x: rect.minX + 0.2, y: rect.minY + 0.4),
          to: CGPoint(x: rect.maxX - 0.2, y: rect.minY + 0.4), sag: 0.5, count: 6, seed: index
        ).draw(context, moment: moment)
      }
    }
  }

  /// Someone on the left bench with a laptop open, its screen lighting their face after dark.
  static let sitter = ViewRhythm(seed: 531, slot: 120, chance: 0.7, length: 70...110)

  private func benchSitter(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.weather != .rain, moment.look.weather != .snow,
      Self.sitter.pass(at: moment.now) != nil
    else { return }
    let seat = CGPoint(x: 33, y: 44.2)
    let shade = moment.palette.street.lit(-0.38)
    let coat = shade.mixed(with: ViewColour(0x5A6AA8), by: moment.look.isDark ? 0.25 : 0.5)
    // Seated: body on the bench, legs down, head bent over the screen.
    ViewKit.rect(context, CGRect(x: seat.x - 0.9, y: seat.y - 3.4, width: 1.8, height: 3.4), coat)
    ViewKit.rect(context, CGRect(x: seat.x - 0.2, y: seat.y, width: 1.8, height: 0.5), shade)
    ViewKit.rect(context, CGRect(x: seat.x + 1.2, y: seat.y, width: 0.45, height: 1.6), shade)
    ViewKit.circle(context, CGPoint(x: seat.x + 0.3, y: seat.y - 4), 0.65, shade)
    let screen = ViewColour(0xCFE4FF)
    var lid = Path()
    lid.move(to: CGPoint(x: seat.x + 1.2, y: seat.y - 0.6))
    lid.addLine(to: CGPoint(x: seat.x + 2.2, y: seat.y - 2.2))
    context.stroke(
      lid, with: .color(screen.color(moment.look.isDark ? 0.9 : 0.4)), lineWidth: 0.35)
    if moment.look.isDark {
      let flicker = 0.85 + 0.15 * sin(moment.now * 1.7)
      ViewKit.glow(context, CGPoint(x: seat.x + 1.4, y: seat.y - 2.4), 3.4, screen, 0.45 * flicker)
    }
  }

  /// A frisbee thrown back and forth across the lawn by day, between two people.
  private func frisbee(_ context: GraphicsContext, moment: ViewMoment) {
    guard !moment.look.isDark, moment.look.weather == .clear else { return }
    let throwers = [CGPoint(x: 26, y: 49), CGPoint(x: 70, y: 48)]
    for (index, thrower) in throwers.enumerated() {
      ViewWalker.figure(
        context, at: thrower, height: 6.4, facing: index == 0 ? 1 : -1, kind: .walker,
        coat: index == 0 ? 0xE5503A : 0x5BA8FF, plane: .street, moment: moment, walking: false)
    }
    guard let pass = Self.frisbee.pass(at: moment.now) else { return }
    let point = Self.frisbeePoint(pass)
    context.fill(
      Path(ellipseIn: CGRect(x: point.x - 0.8, y: point.y - 0.25, width: 1.6, height: 0.5)),
      with: .color(ViewColour(0xFFD166).color()))
  }

  static func frisbeePoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    let p = CGFloat(pass.progress)
    let share = pass.variant < 0.5 ? p : 1 - p
    return CGPoint(x: 27 + 42 * share, y: 44 - 1 * share - 7 * sin(.pi * p))
  }

  /// A squirrel dashing over the grass in short bursts, by day.
  private func squirrel(_ context: GraphicsContext, moment: ViewMoment) {
    guard !moment.look.isDark, let pass = Self.squirrel.pass(at: moment.now) else { return }
    let point = Self.squirrelPoint(pass)
    let colour = moment.palette.street.mixed(with: ViewColour(0x8A6A4A), by: 0.5)
    let hop = abs(sin(moment.now * 14)) * 0.5
    ViewKit.circle(context, CGPoint(x: point.x, y: point.y - 0.6 - hop), 0.7, colour)
    ViewKit.circle(
      context, CGPoint(x: point.x + (pass.variant < 0.5 ? -1 : 1), y: point.y - 1.6 - hop), 0.7,
      colour.lit(0.05))
  }

  static func squirrelPoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    // Dashes, stops, dashes: eased in three bursts.
    let p = pass.progress
    let bursts = (p * 3).rounded(.down) + pow((p * 3).truncatingRemainder(dividingBy: 1), 0.4)
    let share = CGFloat(min(bursts / 3, 1))
    let x = pass.variant < 0.5 ? 4 + 92 * share : 96 - 92 * share
    return CGPoint(x: x, y: 47 + 3 * CGFloat(pass.variant))
  }

  func headlight(at now: Double) -> ViewHeadlight? { nil }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if !moment.look.isDark, moment.look.weather == .clear,
      let pass = Self.frisbee.pass(at: moment.now)
    {
      return ViewInterest(
        point: Self.frisbeePoint(pass), plane: .street, paw: false, id: pass.index)
    }
    if !moment.look.isDark, let pass = Self.squirrel.pass(at: moment.now) {
      return ViewInterest(
        point: Self.squirrelPoint(pass), plane: .street, paw: false, id: pass.index)
    }
    for walker in Self.walkers {
      if let interest = walker.interest(at: moment.now) { return interest }
    }
    return nil
  }
}
