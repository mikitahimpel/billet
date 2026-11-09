import CoreGraphics
import Foundation
import Pet
import SwiftUI

extension ForestCabin {
  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far:
      Self.shootingStar.draw(context, moment: moment)
    case .middle: break
    case .street:
      for window in Self.windows {
        ViewKit.litWindow(
          context, window,
          level: Self.homeLight(moment) * (0.92 + 0.08 * Self.fireFlicker(moment.now)))
      }
      smoke(context, moment: moment)
      lantern(context, moment: moment)
      campfire(context, moment: moment)
      deer(context, moment: moment)
      owl(context, moment: moment)
      Self.fireflies.draw(context, moment: moment)
    case .near:
      bough(context, moment: moment)
    }
  }

  static func homeLight(_ moment: ViewMoment) -> Double {
    switch moment.look.hour {
    case .night, .dusk: moment.lamps
    case .morning: 0.45
    case .day: 0
    }
  }

  /// From 0 to 1.
  static func fireFlicker(_ now: Double) -> Double {
    let a = sin(now * 9.1)
    let b = sin(now * 14.7 + 1.3)
    let c = sin(now * 23.3 + 0.4)
    return 0.6 + 0.2 * a + 0.12 * b * b + 0.08 * c
  }

  private func smoke(_ context: GraphicsContext, moment: ViewMoment) {
    let top = CGPoint(x: Self.chimney.midX, y: Self.chimney.minY - 0.2)
    let colour = moment.palette.middle.lit(moment.look.isDark ? 0.3 : 0.5)
    let wind = moment.look.weather == .rain ? 2.0 : 1
    for puff in 0..<7 {
      let cycle = moment.now / 9 + Double(puff) / 7
      let p = cycle - cycle.rounded(.down)
      let rise = CGFloat(p) * 18
      let curl = CGFloat(sin(moment.now * 0.5 + Double(puff) * 1.9 + p * 4)) * 1.4 * CGFloat(p)
      let centre = CGPoint(x: top.x + CGFloat(p * p * 9 * wind) + curl, y: top.y - rise)
      let radius = 0.8 + CGFloat(p) * 2.6
      let alpha = 0.32 * min(p / 0.1, 1) * (1 - p)
      ViewKit.circle(context, centre, radius, colour, alpha)
    }
  }

  private func lantern(_ context: GraphicsContext, moment: ViewMoment) {
    let point = Self.lantern
    let level = Self.homeLight(moment)
    let frame = moment.palette.street.lit(-0.3)
    ViewKit.rect(context, CGRect(x: point.x - 0.6, y: point.y, width: 1.2, height: 1.6), frame)
    guard level > 0 else { return }
    let flicker = Self.fireFlicker(moment.now + 3)
    ViewKit.rect(
      context, CGRect(x: point.x - 0.4, y: point.y + 0.3, width: 0.8, height: 1),
      ViewPalette.lampCore, level)
    ViewKit.glow(
      context, CGPoint(x: point.x, y: point.y + 0.8), 6 + 1.2 * CGFloat(flicker), ViewPalette.lamp,
      0.45 * level)
  }

  private func campfire(_ context: GraphicsContext, moment: ViewMoment) {
    let look = moment.look
    guard look.hour != .day, look.weather != .rain else { return }
    let fire = Self.fire
    let level = look.hour == .morning ? 0.4 : max(moment.lamps, 0.3)
    let flicker = Self.fireFlicker(moment.now)
    ViewKit.glow(
      context, CGPoint(x: fire.x, y: fire.y - 1.6), 12 + 3 * CGFloat(flicker), ViewColour(0xFF9A4A),
      0.4 * level * flicker)
    let colours = [ViewColour(0xFF7A3A), ViewColour(0xFFB050), ViewColour(0xFFE2A0)]
    for (index, colour) in colours.enumerated() {
      let scale = 1 - CGFloat(index) * 0.28
      let lick = CGFloat(sin(moment.now * (7 + Double(index) * 3) + Double(index))) * 0.5
      let height = (3.2 + 1.2 * CGFloat(flicker)) * scale
      var flame = Path()
      flame.move(to: CGPoint(x: fire.x - 1.8 * scale, y: fire.y - 0.6))
      flame.addQuadCurve(
        to: CGPoint(x: fire.x + lick, y: fire.y - 0.6 - height),
        control: CGPoint(x: fire.x - 1.8 * scale, y: fire.y - 0.6 - height * 0.6))
      flame.addQuadCurve(
        to: CGPoint(x: fire.x + 1.8 * scale, y: fire.y - 0.6),
        control: CGPoint(x: fire.x + 1.8 * scale, y: fire.y - 0.6 - height * 0.5))
      flame.closeSubpath()
      context.fill(flame, with: .color(colour.color(level * 0.95)))
    }
    for spark in 0..<4 {
      let cycle = moment.now / 2.2 + Double(spark) / 4
      let p = cycle - cycle.rounded(.down)
      let drift = CGFloat(ViewRhythm.hash(spark + Int(cycle.rounded(.down)) % 97, seed: 921)) - 0.5
      let point = CGPoint(x: fire.x + drift * 4 * CGFloat(p), y: fire.y - 3 - CGFloat(p) * 9)
      ViewKit.circle(context, point, 0.18, ViewColour(0xFFD080), level * (1 - p))
    }
  }

  static func deerX(_ pass: ViewRhythm.Pass) -> CGFloat {
    let p = pass.progress
    let share: Double
    switch p {
    case ..<0.35: share = p / 0.35 * 0.45
    case ..<0.65: share = 0.45 + (p - 0.35) / 0.3 * 0.1
    default: share = 0.55 + (p - 0.65) / 0.35 * 0.45
    }
    return pass.variant < 0.5 ? -15 + 130 * CGFloat(share) : 115 - 130 * CGFloat(share)
  }

  private func deer(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = Self.deer.pass(at: moment.now) else { return }
    let x = Self.deerX(pass)
    let facing: CGFloat = pass.variant < 0.5 ? 1 : -1
    let grazing = pass.progress > 0.38 && pass.progress < 0.62
    let walking = !grazing
    let colour = moment.palette.street.lit(-0.25).mixed(
      with: ViewColour(0x8A5A3A), by: moment.look.isDark ? 0.15 : 0.45)
    var body = context
    body.translateBy(x: x, y: Self.clearing + 1.4)
    body.scaleBy(x: facing, y: 1)
    let step = walking ? CGFloat(sin(moment.now * 5)) * 0.5 : 0
    for (legX, phase) in [(-1.6, step), (-1.0, -step), (1.2, -step), (1.8, step)]
      as [(CGFloat, CGFloat)]
    {
      body.fill(
        Path(CGRect(x: legX + phase * 0.4, y: -3, width: 0.3, height: 3)),
        with: .color(colour.color()))
    }
    body.fill(
      Path(roundedRect: CGRect(x: -2.2, y: -4.6, width: 4.6, height: 2), cornerRadius: 1),
      with: .color(colour.color()))
    ViewKit.circle(body, CGPoint(x: -2, y: -3.8), 0.5, colour.lit(0.5))
    var neck = Path()
    let head = grazing ? CGPoint(x: 3.6, y: -0.8) : CGPoint(x: 3.2, y: -6.6)
    neck.move(to: CGPoint(x: 1.6, y: -4.2))
    neck.addLine(to: CGPoint(x: head.x - 0.4, y: head.y + 0.4))
    body.stroke(neck, with: .color(colour.color()), lineWidth: 1)
    body.fill(
      Path(ellipseIn: CGRect(x: head.x - 0.7, y: head.y - 0.5, width: 1.7, height: 1)),
      with: .color(colour.color()))
    var ear = Path()
    ear.move(to: CGPoint(x: head.x - 0.4, y: head.y - 0.4))
    ear.addLine(to: CGPoint(x: head.x - 1.1, y: head.y - 1.3))
    body.stroke(ear, with: .color(colour.color()), lineWidth: 0.3)
  }

  private func owl(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.isDark || moment.look.hour == .morning else { return }
    let point = Self.owl
    let colour = moment.palette.street.lit(-0.2).mixed(
      with: ViewColour(0x8A7058), by: moment.look.isDark ? 0.2 : 0.4)
    context.fill(
      Path(ellipseIn: CGRect(x: point.x - 1.1, y: point.y - 2.6, width: 2.2, height: 3)),
      with: .color(colour.color()))
    let look = sin(moment.now * 0.23) + 0.6 * sin(moment.now * 0.61 + 1)
    let turn = CGFloat(look > 0.9 ? 0.4 : look < -0.9 ? -0.4 : 0)
    let head = CGPoint(x: point.x + turn, y: point.y - 3)
    ViewKit.circle(context, head, 1.05, colour)
    for side in [-1.0, 1.0] as [CGFloat] {
      var tuft = Path()
      tuft.move(to: CGPoint(x: head.x + side * 0.9, y: head.y - 0.4))
      tuft.addLine(to: CGPoint(x: head.x + side * 0.8, y: head.y - 1.5))
      tuft.addLine(to: CGPoint(x: head.x + side * 0.3, y: head.y - 0.8))
      tuft.closeSubpath()
      context.fill(tuft, with: .color(colour.color()))
    }
    let blink = (moment.now / 4.7).truncatingRemainder(dividingBy: 1) > 0.95
    let eye = ViewColour(0xFFD25A)
    for side in [-0.42, 0.42] as [CGFloat] {
      let centre = CGPoint(x: head.x + side + turn * 0.5, y: head.y)
      if blink {
        ViewKit.rect(
          context, CGRect(x: centre.x - 0.3, y: centre.y - 0.05, width: 0.6, height: 0.1), eye, 0.6)
      } else {
        ViewKit.circle(context, centre, 0.3, eye, moment.look.isDark ? 0.95 : 0.6)
        ViewKit.circle(context, centre, 0.13, ViewColour(0x1A1008))
      }
    }
  }

  private func bough(_ context: GraphicsContext, moment: ViewMoment) {
    let wind = moment.look.weather == .rain ? 1.8 : 1
    let t = moment.now
    let sway = (0.6 * sin(t * 0.6) + 0.3 * sin(t * 1.7 + 1) + 0.12 * sin(t * 3.9)) * wind
    var bough = context
    bough.translateBy(x: -14, y: -12)
    bough.rotate(by: .degrees(sway * 1.4))
    let colour = moment.palette.near
    let stem = Path { path in
      path.move(to: .zero)
      path.addQuadCurve(to: CGPoint(x: 34, y: 14), control: CGPoint(x: 18, y: 2))
    }
    bough.stroke(stem, with: .color(colour.lit(-0.1).color()), lineWidth: 1)
    var needles = Path()
    for index in 0..<22 {
      let share = CGFloat(index) / 21
      let u = 1 - share
      let point = CGPoint(
        x: 2 * u * share * 18 + share * share * 34, y: 2 * u * share * 2 + share * share * 14)
      let length = 4.4 - share * 2
      let flutter = CGFloat(sin(t * 2.1 + Double(index))) * 0.3
      needles.move(to: point)
      needles.addLine(to: CGPoint(x: point.x + length * 0.5, y: point.y - length + flutter))
      needles.move(to: point)
      needles.addLine(to: CGPoint(x: point.x + length * 0.6, y: point.y + length * 0.9 + flutter))
    }
    bough.stroke(needles, with: .color(colour.color()), lineWidth: 0.55)
    if moment.look.weather == .snow {
      for index in 0..<5 {
        let share = CGFloat(index) / 4
        let u = 1 - share
        let point = CGPoint(
          x: 2 * u * share * 18 + share * share * 34, y: 2 * u * share * 2 + share * share * 14)
        bough.fill(
          Path(ellipseIn: CGRect(x: point.x - 1.6, y: point.y - 1.4, width: 3.2, height: 1)),
          with: .color(ViewKit.snow(moment.look).color(0.8)))
      }
    }
  }

  func headlight(at now: Double) -> ViewHeadlight? { nil }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if let pass = Self.deer.pass(at: moment.now) {
      let x = Self.deerX(pass)
      if x > 0, x < 100 {
        return ViewInterest(
          point: CGPoint(x: x, y: Self.clearing - 3), plane: .street, paw: false, id: pass.index)
      }
    }
    return Self.shootingStar.interest(at: moment)
  }
}
