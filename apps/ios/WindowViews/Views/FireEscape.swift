import CoreGraphics
import Foundation
import Pet
import SwiftUI

struct FireEscape: ViewRecipe {
  static let streetBase: CGFloat = 46
  static let roadway = ViewRoad(
    line: 50.8, kerb: streetBase,
    cars: ViewRhythm(seed: 601, slot: 14, chance: 0.75, length: 4...6),
    length: 10.5, bodies: [0xF2C230, 0xF2C230, 0xF2C230, 0x3A3A40, 0x23324A])
  static let lamp = ViewStreetLamp(head: CGPoint(x: 92, y: 18), ground: streetBase)
  static let stack = CGPoint(x: 36, y: 49)
  static let bodega = CGRect(x: 52, y: 38, width: 26, height: 8)
  static let rail: CGFloat = 46.6
  static let pigeons = [
    ViewRhythm(seed: 611, slot: 50, chance: 0.7, length: 18...40),
    ViewRhythm(seed: 612, slot: 70, chance: 0.5, length: 14...30),
  ]
  static let spire = CGPoint(x: 18, y: -4)

  var moon: CGPoint { CGPoint(x: 70, y: -16) }
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

  // MARK: - Far: the skyline

  static let towers: [(x: CGFloat, width: CGFloat, top: CGFloat)] = [
    (-42, 9, 14), (-32, 7, 20), (-24, 10, 10), (-12, 6, 17), (-5, 9, 22), (5, 7, 12), (24, 8, 16),
    (33, 10, 8), (44, 6, 18), (51, 9, 13), (61, 11, 21), (73, 7, 11), (81, 9, 15), (91, 6, 19),
    (98, 10, 9), (109, 8, 16), (118, 11, 12), (130, 9, 18),
  ]

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let base: CGFloat = 36
    for (index, tower) in Self.towers.enumerated() {
      let tone = colour.lit(index % 3 == 0 ? 0.03 : index % 3 == 1 ? -0.02 : 0)
      ViewKit.rect(
        context, CGRect(x: tower.x, y: tower.top, width: tower.width, height: base - tower.top),
        tone)
      if index % 4 == 1 {
        ViewKit.rect(
          context,
          CGRect(
            x: tower.x + tower.width * 0.3, y: tower.top - 2, width: tower.width * 0.4, height: 2),
          tone)
      }
      var y = tower.top + 1.4
      var row = 0
      while y < base - 1 {
        var x = tower.x + 1
        var column = 0
        while x < tower.x + tower.width - 1 {
          let id = index * 400 + row * 20 + column
          if look.isDark, ViewRhythm.hash(id, seed: 621) < look.palette.litShare * 0.7 {
            ViewKit.rect(
              context, CGRect(x: x, y: y, width: 0.7, height: 0.6), ViewPalette.lamp, 0.55)
          } else if !look.isDark {
            ViewKit.rect(context, CGRect(x: x, y: y, width: 0.7, height: 0.6), tone.lit(0.06), 0.8)
          }
          x += 1.6
          column += 1
        }
        y += 1.6
        row += 1
      }
    }
    let spire = Self.spire
    let shade = colour.lit(0.05)
    for (step, width) in [(0, 12.0), (1, 9), (2, 6.4), (3, 4)] as [(Int, CGFloat)] {
      let top = 32 - CGFloat(step + 1) * 7.6
      ViewKit.rect(
        context, CGRect(x: spire.x - width / 2, y: top, width: width, height: 36 - top),
        shade.lit(Double(step) * 0.015))
    }
    ViewKit.rect(context, CGRect(x: spire.x - 0.4, y: spire.y, width: 0.8, height: 6), shade)
    ViewKit.ground(context, top: base, colour: colour.lit(-0.02))
  }

  // MARK: - Middle: tenements across the street

  static let buildings: [(x: CGFloat, width: CGFloat, top: CGFloat, brick: UInt32)] = [
    (-40, 20, 14, 0x8A4A38), (-20, 18, 11, 0x6A4A42), (-2, 22, 15, 0x9A5A40),
    (20, 20, 12, 0x7A3E34),
    (40, 18, 16, 0x5A4A50), (58, 22, 10, 0x8A4A38), (80, 20, 13, 0x6A4A42), (100, 22, 15, 0x9A5A40),
    (122, 20, 12, 0x7A3E34),
  ]
  static let middleBase: CGFloat = 40

  static let middleWindows: [ViewLitWindow] = buildings.indices.flatMap(windows(of:))

  private static func windows(of index: Int) -> [ViewLitWindow] {
    let building = buildings[index]
    let gap: CGFloat = (building.width - 6) / 2.6
    var windows: [ViewLitWindow] = []
    for floor in 0..<4 {
      for column in 0..<3 {
        let rect = CGRect(
          x: building.x + 3 + CGFloat(column) * gap, y: building.top + 3 + CGFloat(floor) * 5.6,
          width: 2.2, height: 3.2)
        windows.append(
          ViewLitWindow(
            id: 800 + index * 20 + floor * 3 + column, rect: rect, plane: .middle,
            isTV: (index + floor * 2 + column) % 9 == 4))
      }
    }
    return windows
  }

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    for (index, building) in Self.buildings.enumerated() {
      let brick = colour.mixed(with: ViewColour(building.brick), by: look.isDark ? 0.2 : 0.38)
      ViewKit.rect(
        context,
        CGRect(
          x: building.x, y: building.top, width: building.width,
          height: Self.middleBase - building.top),
        brick)
      ViewKit.rect(
        context,
        CGRect(x: building.x - 0.4, y: building.top - 1, width: building.width + 0.8, height: 1.2),
        brick.lit(0.1))
      for window in Self.middleWindows where window.id / 20 == 40 + index {
        ViewKit.windowFrame(context, window.rect, brick)
        ViewKit.rect(
          context,
          CGRect(
            x: window.rect.minX - 0.3, y: window.rect.minY - 0.5, width: window.rect.width + 0.6,
            height: 0.5), brick.lit(0.12))
      }
      if index % 2 == 0 {
        let iron = colour.lit(-0.3)
        let left = building.x + 1.6
        let right = building.x + building.width * 0.62
        for floor in 0..<4 {
          let y = building.top + 6.6 + CGFloat(floor) * 5.6
          ViewKit.rect(context, CGRect(x: left, y: y, width: right - left, height: 0.4), iron)
          ViewKit.rect(context, CGRect(x: left, y: y - 1.8, width: right - left, height: 0.2), iron)
          var x = left
          while x <= right {
            ViewKit.rect(context, CGRect(x: x, y: y - 1.8, width: 0.15, height: 1.8), iron)
            x += 1
          }
          if floor < 3 {
            var stair = Path()
            let goingRight = floor % 2 == 0
            stair.move(to: CGPoint(x: goingRight ? left + 1 : right - 1, y: y))
            stair.addLine(to: CGPoint(x: goingRight ? right - 1 : left + 1, y: y + 5.6))
            context.stroke(stair, with: .color(iron.color()), lineWidth: 0.35)
          }
        }
      }
      if index % 3 == 1 {
        let tank = colour.lit(-0.05).mixed(with: ViewColour(0x6A4A30), by: look.isDark ? 0.15 : 0.3)
        let x = building.x + building.width * 0.6
        for leg in [-2.0, 2] as [CGFloat] {
          ViewKit.rect(
            context, CGRect(x: x + leg - 0.2, y: building.top - 4, width: 0.4, height: 3.4),
            tank.lit(-0.15))
        }
        ViewKit.rect(context, CGRect(x: x - 2.6, y: building.top - 9, width: 5.2, height: 5), tank)
        for band in [0.25, 0.75] as [CGFloat] {
          ViewKit.rect(
            context, CGRect(x: x - 2.6, y: building.top - 9 + 5 * band, width: 5.2, height: 0.25),
            tank.lit(-0.2))
        }
        var cap = Path()
        cap.move(to: CGPoint(x: x - 2.9, y: building.top - 9))
        cap.addLine(to: CGPoint(x: x, y: building.top - 11))
        cap.addLine(to: CGPoint(x: x + 2.9, y: building.top - 9))
        cap.closeSubpath()
        context.fill(cap, with: .color(tank.lit(-0.08).color()))
      }
    }
    for (index, window) in Self.middleWindows.enumerated() where index % 7 == 3 {
      ViewKit.rect(
        context,
        CGRect(
          x: window.rect.minX - 0.2, y: window.rect.maxY - 1.2, width: window.rect.width + 0.4,
          height: 1.4), colour.lit(0.12))
    }
    ViewKit.ground(context, top: Self.middleBase, colour: colour.lit(-0.05))
  }

  // MARK: - Street

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let base = Self.streetBase
    ViewKit.rect(context, CGRect(x: -45, y: base - 9, width: 190, height: 9), colour.lit(0.02))
    for x in stride(from: -40.0, to: 140, by: 13) where x < 48 || x > 80 {
      ViewKit.rect(context, CGRect(x: x, y: base - 6.4, width: 7, height: 5), colour.lit(-0.12))
      ViewKit.rect(
        context, CGRect(x: x + 8.6, y: base - 7, width: 2.6, height: 7), colour.lit(-0.25))
    }
    let bodega = Self.bodega
    ViewKit.rect(context, bodega.insetBy(dx: -1, dy: 0), colour.lit(-0.05))
    ViewKit.rect(
      context, CGRect(x: bodega.minX + 1, y: bodega.minY + 2.6, width: 16, height: 4.6),
      colour.lit(-0.2))
    ViewKit.rect(
      context, CGRect(x: bodega.maxX - 6, y: bodega.minY + 2.2, width: 4, height: 5.8),
      colour.lit(-0.3))
    let awning = ViewColour(0x2E8A4E).mixed(with: colour, by: look.isDark ? 0.55 : 0.25)
    var canopy = Path()
    canopy.move(to: CGPoint(x: bodega.minX - 1.4, y: bodega.minY - 1.2))
    canopy.addLine(to: CGPoint(x: bodega.maxX + 1.4, y: bodega.minY - 1.2))
    canopy.addLine(to: CGPoint(x: bodega.maxX + 2.4, y: bodega.minY + 1.8))
    canopy.addLine(to: CGPoint(x: bodega.minX - 2.4, y: bodega.minY + 1.8))
    canopy.closeSubpath()
    context.fill(canopy, with: .color(awning.color()))
    var x = bodega.minX - 2.4
    while x < bodega.maxX + 2.4 {
      ViewKit.circle(context, CGPoint(x: x + 0.8, y: bodega.minY + 1.8), 0.8, awning)
      x += 1.6
    }
    let stack = Self.stack
    for band in 0..<4 {
      let y = stack.y - CGFloat(band + 1) * 1.4
      let half = 1.6 - CGFloat(band) * 0.22
      ViewKit.rect(
        context, CGRect(x: stack.x - half, y: y, width: half * 2, height: 1.4),
        (band % 2 == 0 ? ViewColour(0xFF7A2E) : ViewColour(0xF4F1EA)).mixed(
          with: colour, by: look.isDark ? 0.55 : 0.2))
    }
    ViewKit.rect(
      context, CGRect(x: -45, y: base, width: 190, height: 1.2),
      colour.lit(look.isDark ? 0.05 : 0.14))
    ViewKit.ground(context, top: base + 1.2, colour: colour.lit(-0.2))
    for x in stride(from: -40.0, to: 140, by: 9) {
      ViewKit.rect(
        context, CGRect(x: x, y: 53, width: 4, height: 0.3), ViewColour(0xFFD166),
        look.isDark ? 0.25 : 0.5)
    }
    ViewKit.streetLampPost(
      context, x: Self.lamp.head.x + 5, top: Self.lamp.head.y - 0.6, base: base + 1.2,
      colour: colour.lit(-0.25))
  }

  // MARK: - Near: our own fire escape

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let rail = Self.rail
    // Painted iron, a shade lighter than the dark beyond it, so the railing reads in front.
    let iron = colour.lit(look.isDark ? 0.1 : -0.05)
    ViewKit.ground(context, top: 55, colour: iron)
    ViewKit.rect(context, CGRect(x: -50, y: rail, width: 200, height: 0.9), iron)
    ViewKit.rect(context, CGRect(x: -50, y: rail + 4.4, width: 200, height: 0.4), iron)
    var x: CGFloat = -50
    while x < 150 {
      ViewKit.rect(context, CGRect(x: x, y: rail, width: 0.35, height: 9), iron)
      x += 2.2
    }
    var stringer = Path()
    stringer.move(to: CGPoint(x: -8, y: rail + 2))
    stringer.addLine(to: CGPoint(x: -30, y: -20))
    stringer.addLine(to: CGPoint(x: -26, y: -20))
    stringer.addLine(to: CGPoint(x: -4, y: rail + 2))
    stringer.closeSubpath()
    context.fill(stringer, with: .color(iron.color()))
    var step: CGFloat = 0
    while step < 1 {
      let y = rail + 2 - (rail + 22) * step
      let left = -8 - 22 * step
      ViewKit.rect(context, CGRect(x: left - 1, y: y, width: 6, height: 0.5), iron)
      step += 0.08
    }
    let pot = ViewColour(0xC0603A).mixed(with: colour, by: look.isDark ? 0.6 : 0.3)
    var basil = Path()
    basil.move(to: CGPoint(x: 70, y: 55))
    basil.addLine(to: CGPoint(x: 70.6, y: 50.6))
    basil.addLine(to: CGPoint(x: 76.4, y: 50.6))
    basil.addLine(to: CGPoint(x: 77, y: 55))
    basil.closeSubpath()
    context.fill(basil, with: .color(pot.color()))
    let leaf = colour.mixed(with: ViewColour(0x3F8A4E), by: look.isDark ? 0.25 : 0.55)
    for index in 0..<7 {
      let a = CGFloat(ViewRhythm.hash(index, seed: 631))
      ViewKit.circle(
        context, CGPoint(x: 71 + CGFloat(index) * 0.9, y: 49.4 - a * 2.4), 1.1,
        leaf.lit(Double(index % 2) * 0.05))
    }
    ViewKit.rect(context, CGRect(x: 81, y: 52, width: 2.6, height: 3), pot)
    context.fill(
      Path(roundedRect: CGRect(x: 81.5, y: 48.6, width: 1.6, height: 3.6), cornerRadius: 0.8),
      with: .color(leaf.lit(-0.05).color()))
  }

  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far:
      let on = sin(moment.now * 1.6) > 0.3
      if on {
        ViewKit.circle(context, Self.spire, 0.5, ViewColour(0xFF3B3B))
        ViewKit.glow(context, Self.spire, 3, ViewColour(0xFF3B3B), 0.6)
      }
    case .middle:
      ViewWindows.draw(Self.middleWindows, context, moment: moment)
      neighbour(context, moment: moment)
    case .street:
      bodegaLights(context, moment: moment)
      steam(context, moment: moment)
      Self.lamp.draw(context, moment: moment)
      Self.roadway.draw(context, moment: moment)
    case .near:
      ViewLightString(
        from: CGPoint(x: -4, y: Self.rail + 0.6), to: CGPoint(x: 104, y: Self.rail + 0.6),
        sag: 1.4, count: 18, seed: 6
      ).draw(context, moment: moment)
      for (index, rhythm) in Self.pigeons.enumerated() {
        pigeon(context, moment: moment, rhythm: rhythm, index: index)
      }
    }
  }

  static let neighbourOut = ViewRhythm(seed: 651, slot: 100, chance: 0.6, length: 50...85)

  private func neighbour(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.weather != .rain, Self.neighbourOut.pass(at: moment.now) != nil else {
      return
    }
    let building = Self.buildings[4]
    let landing = CGPoint(x: building.x + 6, y: building.top + 6.6 + 5.6)
    let dark = moment.look.isDark
    ViewWalker.figure(
      context, at: landing, height: 4.2, facing: 1, kind: dark ? .phone : .walker, coat: 0xC8A050,
      plane: .middle, moment: moment, walking: false)
    let pot = ViewColour(0xC0603A).mixed(with: moment.palette.middle, by: dark ? 0.6 : 0.3)
    for dx in [3.0, 4.6, 6.2] as [CGFloat] {
      ViewKit.rect(context, CGRect(x: landing.x + dx, y: landing.y - 1, width: 1, height: 1), pot)
      ViewKit.circle(
        context, CGPoint(x: landing.x + dx + 0.5, y: landing.y - 1.4), 0.7,
        ViewColour(0x3F8A4E).mixed(with: moment.palette.middle, by: dark ? 0.6 : 0.3))
    }
    guard !dark else { return }
    let spout = CGPoint(x: landing.x + 2, y: landing.y - 2.6)
    ViewKit.rect(
      context, CGRect(x: landing.x + 0.6, y: landing.y - 3, width: 1.2, height: 0.9),
      ViewColour(0x5BA8FF).mixed(with: moment.palette.middle, by: 0.3))
    for drop in 0..<5 {
      let p = (moment.now * 1.6 + Double(drop) / 5).truncatingRemainder(dividingBy: 1)
      ViewKit.circle(
        context, CGPoint(x: spout.x + 0.8 + CGFloat(p) * 1.4, y: spout.y + CGFloat(p * p) * 2.4),
        0.14, moment.palette.skyMiddle.lit(0.5), 0.8 * (1 - p))
    }
  }

  private func bodegaLights(_ context: GraphicsContext, moment: ViewMoment) {
    let bodega = Self.bodega
    let window = CGRect(x: bodega.minX + 1, y: bodega.minY + 2.6, width: 16, height: 4.6)
    let dark = moment.look.isDark
    ViewKit.rect(context, window, ViewColour(0xFFF2D8), dark ? 0.6 : 0.2)
    ViewKit.glow(
      context, CGPoint(x: window.midX, y: window.maxY), 12, ViewPalette.lamp, dark ? 0.3 : 0.08)
    let stutter = ViewRhythm(seed: 641, slot: 12, chance: 0.4, length: 0.4...0.9).pass(
      at: moment.now)
    let hum = stutter.map { sin($0.progress * 40) > 0 ? 0.2 : 1 } ?? 1
    let neon = ViewColour(0xFF4D7A)
    let sign = CGRect(x: window.minX + 2, y: window.minY + 0.8, width: 7, height: 1.8)
    context.stroke(
      Path(roundedRect: sign, cornerRadius: 0.8), with: .color(neon.color(hum * (dark ? 1 : 0.7))),
      lineWidth: 0.35)
    ViewKit.rect(
      context, sign.insetBy(dx: 1.2, dy: 0.7), ViewColour(0x5BD8FF), hum * (dark ? 0.9 : 0.6))
    ViewKit.glow(
      context, CGPoint(x: sign.midX, y: sign.midY), 5, neon, 0.35 * hum * (dark ? 1 : 0.3))
  }

  private func steam(_ context: GraphicsContext, moment: ViewMoment) {
    let stack = Self.stack
    let top = CGPoint(x: stack.x, y: stack.y - 5.6)
    let thick = moment.look.weather == .clear ? 1.0 : 1.5
    let colour = moment.palette.skyMiddle.lit(0.45).mixed(with: ViewColour(0xEEF2F7), by: 0.4)
    for index in 0..<14 {
      let p = (moment.now * 0.16 + Double(index) / 14).truncatingRemainder(dividingBy: 1)
      let wobble = sin(moment.now * 0.8 + Double(index) * 1.7) * 2 * p
      let x = top.x + CGFloat(p * 14 + wobble)
      let y = top.y - CGFloat(p * 16)
      let radius = CGFloat(1.4 + p * 5)
      ViewKit.circle(context, CGPoint(x: x, y: y), radius, colour, 0.22 * (1 - p) * thick)
    }
  }

  private func pigeon(
    _ context: GraphicsContext, moment: ViewMoment, rhythm: ViewRhythm, index: Int
  ) {
    guard let pass = rhythm.pass(at: moment.now) else { return }
    let point = Self.pigeonPoint(pass, now: moment.now)
    let flying = pass.progress < 0.08 || pass.progress > 0.92
    let colour = moment.palette.near.lit(moment.look.isDark ? 0.1 : 0.3).mixed(
      with: ViewColour(0x8A90A0), by: moment.look.isDark ? 0.2 : 0.4)
    let facing: CGFloat = pass.variant < 0.5 ? 1 : -1
    var bird = context
    bird.translateBy(x: point.x, y: point.y)
    bird.scaleBy(x: facing, y: 1)
    bird.fill(
      Path(ellipseIn: CGRect(x: -1.6, y: -1.8, width: 3, height: 1.8)), with: .color(colour.color())
    )
    let bob = flying ? 0 : CGFloat(max(0, sin(moment.now * 5 + Double(index)))) * 0.5
    bird.fill(
      Path(ellipseIn: CGRect(x: 0.8 + bob, y: -2.8 + bob * 0.4, width: 1.2, height: 1.2)),
      with: .color(colour.lit(-0.05).color()))
    bird.fill(
      Path(ellipseIn: CGRect(x: 0.9 + bob, y: -1.9 + bob * 0.3, width: 0.8, height: 0.5)),
      with: .color(ViewColour(0x6ABF9A).mixed(with: colour, by: 0.6).color()))
    if flying {
      let flap = CGFloat(sin(moment.now * 30))
      var wings = Path()
      wings.move(to: CGPoint(x: -1.6, y: -1.4 - flap * 1.6))
      wings.addLine(to: CGPoint(x: 0, y: -1.2))
      wings.addLine(to: CGPoint(x: 1.2, y: -1.4 - flap * 1.6))
      bird.stroke(wings, with: .color(colour.color()), lineWidth: 0.5)
    } else {
      bird.fill(
        Path(CGRect(x: -0.2, y: 0, width: 0.2, height: 0.5)),
        with: .color(ViewColour(0xE5806A).color(0.8)))
    }
  }

  static func pigeonPoint(_ pass: ViewRhythm.Pass, now: Double) -> CGPoint {
    let perch = 10 + 80 * CGFloat(pass.variant)
    let p = pass.progress
    let y = rail - 0.2
    if p < 0.08 {
      let t = CGFloat(p / 0.08)
      return CGPoint(x: perch - 20 * (1 - t), y: y - 22 * (1 - t) * (1 - t))
    }
    if p > 0.92 {
      let t = CGFloat((p - 0.92) / 0.08)
      return CGPoint(x: perch + 3 + 24 * t, y: y - 26 * t * t)
    }
    let strut = CGFloat(sin((p - 0.08) * 6)) * 3
    return CGPoint(x: perch + strut, y: y)
  }

  func headlight(at now: Double) -> ViewHeadlight? { Self.roadway.headlight(at: now) }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    for rhythm in Self.pigeons {
      if let pass = rhythm.pass(at: moment.now) {
        let point = Self.pigeonPoint(pass, now: moment.now)
        if point.x > -5, point.x < 105, point.y > -30 {
          return ViewInterest(point: point, plane: .near, paw: false, id: pass.index)
        }
      }
    }
    return Self.roadway.interest(at: moment.now)
  }
}
