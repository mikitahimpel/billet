import CoreGraphics
import Foundation
import Pet
import SwiftUI

extension MistyLake {
  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: sunrise(context, moment: moment)
    case .middle:
      glitter(context, moment: moment, from: 40, rows: 8)
      fishJump(context, moment: moment)
      rainRings(context, moment: moment)
      ducks(context, moment: moment)
      canoe(context, moment: moment)
      mist(context, moment: moment, rows: [35.6, 39.4, 43])
    case .street:
      ViewWindows.draw([Self.boathouseWindow], context, moment: moment)
      Self.lamp.draw(context, moment: moment)
      heron(context, moment: moment)
      mist(context, moment: moment, rows: [48.6])
    case .near: reeds(context, moment: moment)
    }
  }

  /// From 0 to about 1.
  static func mistiness(_ look: ViewLook) -> Double {
    let byHour: Double =
      switch look.hour {
      case .morning: 1
      case .day: 0.25
      case .dusk: 0.5
      case .night: 0.4
      }
    let byWeather: Double =
      switch look.weather {
      case .clear: 1
      case .fog: 1.25
      case .rain: 0.35
      case .snow: 0.6
      }
    return byHour * byWeather
  }

  private func mist(_ context: GraphicsContext, moment: ViewMoment, rows: [CGFloat]) {
    let thick = Self.mistiness(moment.look)
    guard thick > 0.05 else { return }
    let palette = moment.palette
    let colour =
      moment.look.isDark
      ? palette.skyMiddle.lit(0.25) : palette.horizon.mixed(with: ViewColour(0xFFFFFF), by: 0.6)
    let span: CGFloat = 260
    for (row, y) in rows.enumerated() {
      for band in 0..<2 {
        let id = row * 2 + band
        let speed = 0.25 + 0.35 * ViewRhythm.hash(id, seed: 1261)
        let start = span * CGFloat(ViewRhythm.hash(id, seed: 1262))
        let x =
          (start + CGFloat(moment.now * speed)).truncatingRemainder(dividingBy: span) - 80
        var mist = context
        mist.translateBy(x: x, y: y + CGFloat(sin(moment.now * 0.05 + Double(id))) * 0.6)
        mist.scaleBy(x: 1, y: 0.12)
        ViewKit.glow(mist, .zero, 36, colour, 0.32 * thick)
      }
    }
  }

  private func sunrise(_ context: GraphicsContext, moment: ViewMoment) {
    let hour = moment.look.hour
    guard moment.look.weather != .rain else { return }
    let dim = moment.look.weather == .clear ? 1.0 : 0.45
    if hour == .morning || hour == .dusk {
      let sun = Self.sun
      ViewKit.glow(context, sun, 24, ViewColour(0xFFD8A0), 0.5 * dim)
      ViewKit.circle(context, sun, 3.2, ViewColour(0xFFF0D0), 0.95 * dim)
    }
    glitter(context, moment: moment, from: Self.shore + 0.6, rows: 7)
  }

  private func glitter(
    _ context: GraphicsContext, moment: ViewMoment, from top: CGFloat, rows: Int
  ) {
    let hour = moment.look.hour
    guard moment.look.weather == .clear || moment.look.weather == .fog else { return }
    let x: CGFloat
    let colour: ViewColour
    let alpha: Double
    switch hour {
    case .morning, .dusk:
      x = Self.sun.x
      colour = ViewColour(0xFFE6B8)
      alpha = 0.75
    case .night:
      x = moon.x
      colour = ViewColour(0xDDE6FF)
      alpha = 0.4
    case .day:
      x = Self.sun.x
      colour = ViewColour(0xFFFFFF)
      alpha = 0.35
    }
    for row in 0..<rows {
      let y = top + CGFloat(row) * 1.1
      let width = 1.4 + CGFloat(row) * 0.7
      for dash in 0..<2 {
        let id = row * 2 + dash
        let speed = 1.5 + 3 * ViewRhythm.hash(id, seed: 1263)
        let flicker = 0.5 + 0.5 * sin(moment.now * speed + Double(id) * 1.7)
        let shift = (CGFloat(ViewRhythm.hash(id, seed: 1264)) - 0.5) * width * 1.6
        ViewKit.rect(
          context, CGRect(x: x + shift - width / 2, y: y, width: width, height: 0.22), colour,
          alpha * flicker)
      }
    }
  }

  static func canoePoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    let p = CGFloat(pass.progress)
    let x = pass.variant < 0.5 ? -25 + 150 * p : 125 - 150 * p
    return CGPoint(x: x, y: 42 + 3 * CGFloat(pass.variant))
  }

  private func canoe(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = Self.canoe.pass(at: moment.now) else { return }
    let point = Self.canoePoint(pass)
    let facing: CGFloat = pass.variant < 0.5 ? 1 : -1
    let isDark = moment.look.isDark
    let palette = moment.palette
    let hull = palette.middle.lit(-0.2).mixed(with: ViewColour(0xD0683A), by: isDark ? 0.2 : 0.55)
    let wake = Self.water(palette, plane: palette.middle, isDark: isDark).lit(0.22)
    for step in 1...3 {
      let back = CGFloat(step) * 2.6
      let spread = CGFloat(step) * 0.45
      for side in [-1.0, 1.0] as [CGFloat] {
        var line = Path()
        line.move(to: CGPoint(x: point.x - facing * (4 + back), y: point.y + 0.5 + side * spread))
        line.addLine(
          to: CGPoint(x: point.x - facing * (5.6 + back), y: point.y + 0.5 + side * spread * 1.3))
        context.stroke(
          line, with: .color(wake.color(0.5 - 0.12 * Double(step))), lineWidth: 0.14)
      }
    }
    context.fill(
      Path(ellipseIn: CGRect(x: point.x - 5, y: point.y + 0.4, width: 10, height: 1.6)),
      with: .color(hull.lit(-0.3).color(0.3)))
    var boat = Path()
    boat.move(to: CGPoint(x: point.x - 5.2, y: point.y - 1))
    boat.addQuadCurve(
      to: CGPoint(x: point.x + 5.2, y: point.y - 1), control: CGPoint(x: point.x, y: point.y + 1.6))
    boat.closeSubpath()
    context.fill(boat, with: .color(hull.color()))
    let jacket = ViewColour(0xFFC24A).mixed(with: palette.middle, by: isDark ? 0.6 : 0.25)
    context.fill(
      Path(
        roundedRect: CGRect(x: point.x - 0.8, y: point.y - 3.8, width: 1.6, height: 3),
        cornerRadius: 0.6),
      with: .color(jacket.color()))
    ViewKit.circle(
      context, CGPoint(x: point.x, y: point.y - 4.5), 0.75, palette.middle.lit(-0.35))
    let stroke = CGFloat(sin(moment.now * 1.6))
    var paddle = Path()
    paddle.move(to: CGPoint(x: point.x + facing * 0.6, y: point.y - 3.4))
    let blade = CGPoint(x: point.x - facing * (1.2 + 1.6 * stroke), y: point.y + 0.6)
    paddle.addLine(to: blade)
    context.stroke(paddle, with: .color(hull.lit(-0.35).color()), lineWidth: 0.25)
    if stroke > 0.7 {
      context.stroke(
        Path(ellipseIn: CGRect(x: blade.x - 1, y: blade.y - 0.2, width: 2, height: 0.5)),
        with: .color(wake.color(0.45)), lineWidth: 0.12)
    }
  }

  static func duckPoint(_ pass: ViewRhythm.Pass, duck: Int) -> CGPoint {
    let p = CGFloat(pass.progress)
    let leftToRight = pass.variant < 0.5
    let lead = leftToRight ? -15 + 130 * p : 115 - 130 * p
    let x = lead - (leftToRight ? 1 : -1) * CGFloat(duck) * 2.6
    return CGPoint(x: x, y: 47.6 + CGFloat(duck % 2) * 0.4)
  }

  private func ducks(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.hour != .night, let pass = Self.ducks.pass(at: moment.now) else { return }
    let facing: CGFloat = pass.variant < 0.5 ? 1 : -1
    let brown = ViewColour(0x7A5A3A).mixed(
      with: moment.palette.middle, by: moment.look.isDark ? 0.5 : 0.2)
    let beak = ViewColour(0xF0A040).mixed(with: brown, by: 0.2)
    for duck in 0..<4 {
      let point = Self.duckPoint(pass, duck: duck)
      let size: CGFloat = duck == 0 ? 1 : 0.6
      let bob = CGFloat(sin(moment.now * 2.2 + Double(duck))) * 0.12
      context.fill(
        Path(
          ellipseIn: CGRect(
            x: point.x - 1.1 * size, y: point.y - 0.8 * size + bob, width: 2.2 * size,
            height: 0.9 * size)),
        with: .color(brown.color()))
      let head = CGPoint(x: point.x + facing * 0.9 * size, y: point.y - 1.2 * size + bob)
      ViewKit.circle(context, head, 0.45 * size, brown.lit(duck == 0 ? -0.15 : 0.1))
      ViewKit.rect(
        context,
        CGRect(
          x: head.x + (facing > 0 ? 0.3 : -0.8) * size, y: head.y - 0.05, width: 0.5 * size,
          height: 0.2 * size), beak)
      ViewKit.rect(
        context,
        CGRect(x: point.x - 1.6 * size, y: point.y + 0.2, width: 3.2 * size, height: 0.1),
        moment.palette.horizon, 0.35)
    }
  }

  static func fishPoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    let id = Int(pass.index % 10_000)
    return CGPoint(
      x: 14 + 60 * CGFloat(ViewRhythm.hash(id, seed: 1271)),
      y: 40 + 8 * CGFloat(ViewRhythm.hash(id, seed: 1272)))
  }

  private func fishJump(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.weather != .rain, let pass = Self.fish.pass(at: moment.now) else { return }
    let point = Self.fishPoint(pass)
    let p = CGFloat(pass.progress)
    let ring = Self.water(moment.palette, plane: moment.palette.middle, isDark: moment.look.isDark)
      .lit(0.3)
    if p < 0.18 {
      let arc = p / 0.18
      let fish = CGPoint(x: point.x - 1 + 2 * arc, y: point.y - 2.4 * sin(arc * .pi))
      context.fill(
        Path(ellipseIn: CGRect(x: fish.x - 0.6, y: fish.y - 0.25, width: 1.2, height: 0.5)),
        with: .color(ring.color(0.9)))
    }
    for wave in 0..<2 {
      let local = p - 0.15 - CGFloat(wave) * 0.2
      guard local > 0 else { continue }
      let radius = 0.6 + 4 * local
      context.stroke(
        Path(
          ellipseIn: CGRect(
            x: point.x + 1 - radius, y: point.y - radius * 0.25, width: 2 * radius,
            height: radius * 0.5)),
        with: .color(ring.color(0.6 * Double(1 - local))), lineWidth: 0.14)
    }
  }

  private func rainRings(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.weather == .rain else { return }
    let ring = Self.water(moment.palette, plane: moment.palette.middle, isDark: moment.look.isDark)
      .lit(0.25)
    for index in 0..<12 {
      let period = 1 + 0.6 * ViewRhythm.hash(index, seed: 1281)
      let cycle = moment.now / period + ViewRhythm.hash(index, seed: 1282)
      let p = CGFloat(cycle - cycle.rounded(.down))
      let slot = Int(cycle.rounded(.down)) % 997
      let x = -4 + 108 * CGFloat(ViewRhythm.hash(index * 1000 + slot, seed: 1283))
      let y = 39 + 14 * CGFloat(ViewRhythm.hash(index * 1000 + slot, seed: 1284))
      let radius = 0.3 + 1.8 * p
      context.stroke(
        Path(
          ellipseIn: CGRect(
            x: x - radius, y: y - radius * 0.3, width: 2 * radius, height: radius * 0.6)),
        with: .color(ring.color(0.55 * Double(1 - p))), lineWidth: 0.12)
    }
  }

  private func heron(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.hour != .night else { return }
    let feet = Self.heronFeet
    let grey = ViewColour(0x8A96A8).mixed(
      with: moment.palette.street, by: moment.look.isDark ? 0.55 : 0.3)
    var dip: CGFloat = 0
    if let pass = Self.heron.pass(at: moment.now) {
      dip = CGFloat(sin(pass.progress * .pi))
    }
    for dx in [-0.3, 0.4] as [CGFloat] {
      var leg = Path()
      leg.move(to: CGPoint(x: feet.x + dx, y: feet.y))
      leg.addLine(to: CGPoint(x: feet.x + dx * 0.5, y: feet.y - 3.6))
      context.stroke(leg, with: .color(grey.lit(-0.3).color()), lineWidth: 0.16)
    }
    let body = CGPoint(x: feet.x, y: feet.y - 4.4)
    var bodyPath = Path()
    bodyPath.move(to: CGPoint(x: body.x - 1.8, y: body.y + 0.6))
    bodyPath.addQuadCurve(
      to: CGPoint(x: body.x + 1.4, y: body.y - 0.8),
      control: CGPoint(x: body.x - 0.6, y: body.y - 1.4)
    )
    bodyPath.addQuadCurve(
      to: CGPoint(x: body.x - 1.8, y: body.y + 0.6),
      control: CGPoint(x: body.x + 0.6, y: body.y + 1))
    context.fill(bodyPath, with: .color(grey.color()))
    let head = CGPoint(x: body.x + 1.8 + 1.4 * dip, y: body.y - 3.4 + 5.4 * dip)
    var neck = Path()
    neck.move(to: CGPoint(x: body.x + 1.2, y: body.y - 0.6))
    neck.addQuadCurve(to: head, control: CGPoint(x: body.x + 0.4 + 2 * dip, y: body.y - 2))
    context.stroke(neck, with: .color(grey.color()), lineWidth: 0.45)
    ViewKit.circle(context, head, 0.5, grey.lit(0.08))
    var beak = Path()
    beak.move(to: CGPoint(x: head.x + 0.3, y: head.y))
    beak.addLine(to: CGPoint(x: head.x + 2, y: head.y + 0.3 + 0.8 * dip))
    context.stroke(
      beak, with: .color(ViewColour(0xD8A040).mixed(with: grey, by: 0.3).color()), lineWidth: 0.2)
  }

  private func reeds(_ context: GraphicsContext, moment: ViewMoment) {
    let wind = moment.look.weather == .rain ? 1.8 : 1
    let t = moment.now
    let colour = moment.palette.near
    let cattail = ViewColour(0x6A4A30).mixed(with: colour, by: moment.look.isDark ? 0.6 : 0.3)
    for (index, reed) in Self.reeds.enumerated() {
      let sway =
        CGFloat(
          (0.6 * sin(t * 0.8 + Double(index) * 0.7) + 0.3 * sin(t * 2.1 + Double(index)))
            * wind) * 1.4
      let base = CGPoint(x: reed.x, y: 59)
      let tip = CGPoint(x: reed.x + sway + (index % 2 == 0 ? 1 : -1), y: reed.top)
      let control = CGPoint(x: reed.x + sway * 0.3, y: (base.y + reed.top) / 2)
      var leaf = Path()
      leaf.move(to: CGPoint(x: base.x - 0.4, y: base.y))
      leaf.addQuadCurve(to: tip, control: control)
      leaf.addQuadCurve(to: CGPoint(x: base.x + 0.4, y: base.y), control: control)
      leaf.closeSubpath()
      context.fill(leaf, with: .color(colour.lit(index % 3 == 0 ? 0.05 : -0.02).color()))
      if reed.cattail {
        let head = CGPoint(x: tip.x - sway * 0.08, y: reed.top + 3.4)
        context.fill(
          Path(
            roundedRect: CGRect(x: head.x - 0.55, y: head.y - 1.8, width: 1.1, height: 3.6),
            cornerRadius: 0.55),
          with: .color(cattail.color()))
        if moment.look.weather == .snow {
          ViewKit.rect(
            context, CGRect(x: head.x - 0.55, y: head.y - 1.9, width: 1.1, height: 0.5),
            ViewKit.snow(moment.look), 0.85)
        }
      }
    }
  }

  func headlight(at now: Double) -> ViewHeadlight? { nil }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if let pass = Self.canoe.pass(at: moment.now) {
      let point = Self.canoePoint(pass)
      if point.x > 0, point.x < 100 {
        return ViewInterest(point: point, plane: .middle, paw: false, id: pass.index)
      }
    }
    if moment.look.hour != .night, let pass = Self.ducks.pass(at: moment.now) {
      let point = Self.duckPoint(pass, duck: 0)
      if point.x > 0, point.x < 100 {
        return ViewInterest(point: point, plane: .middle, paw: false, id: pass.index)
      }
    }
    if moment.look.weather != .rain, let pass = Self.fish.pass(at: moment.now) {
      return ViewInterest(point: Self.fishPoint(pass), plane: .middle, paw: false, id: pass.index)
    }
    if moment.look.hour != .night, let pass = Self.heron.pass(at: moment.now) {
      return ViewInterest(
        point: CGPoint(x: Self.heronFeet.x + 2, y: Self.heronFeet.y - 4), plane: .street,
        paw: false, id: pass.index)
    }
    return nil
  }
}
