import CoreGraphics
import Foundation
import Pet
import SwiftUI

extension DesertStars {
  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: Self.shooting.draw(context, moment: moment)
    case .middle:
      farCar(context, moment: moment)
      coyote(context, moment: moment)
    case .street:
      ViewKit.litWindow(context, Self.vanWindow, level: moment.lamps)
      Self.fairyLights.draw(context, moment: moment)
      campfire(context, moment: moment)
    case .near: tumbleweed(context, moment: moment)
    }
  }

  static func carX(_ pass: ViewRhythm.Pass) -> CGFloat {
    let p = CGFloat(pass.progress)
    return pass.variant < 0.5 ? -40 + 180 * p : 140 - 180 * p
  }

  private func farCar(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = Self.farCar.pass(at: moment.now) else { return }
    let x = Self.carX(pass)
    let leftToRight = pass.variant < 0.5
    let y = Self.road
    let ahead: CGFloat = leftToRight ? 1 : -1
    if moment.look.isDark {
      ViewKit.glow(
        context, CGPoint(x: x + ahead * 3, y: y - 0.2), 4, ViewPalette.lampCore, 0.3)
      ViewKit.circle(context, CGPoint(x: x + ahead * 0.6, y: y - 0.3), 0.22, ViewPalette.lampCore)
      ViewKit.circle(
        context, CGPoint(x: x - ahead * 0.6, y: y - 0.3), 0.18, ViewColour(0xFF3B3B), 0.8)
    } else {
      ViewKit.rect(
        context, CGRect(x: x - 1, y: y - 0.9, width: 2, height: 0.8),
        moment.palette.middle.lit(-0.3))
      let dust = moment.palette.middle.lit(0.15)
      for puff in 1...3 {
        ViewKit.glow(
          context, CGPoint(x: x - ahead * CGFloat(puff) * 1.6, y: y - 0.6), 1.4,
          dust, 0.25 / Double(puff))
      }
    }
  }

  static func coyotePoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    let p = pass.progress
    let share: Double =
      p < 0.4 ? p / 0.4 * 0.45 : p < 0.6 ? 0.45 : 0.45 + (p - 0.6) / 0.4 * 0.55
    let x = pass.variant < 0.5 ? -15 + 130 * share : 115 - 130 * share
    return CGPoint(x: CGFloat(x), y: Self.road + 2.8)
  }

  private func coyote(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = Self.coyote.pass(at: moment.now) else { return }
    let feet = Self.coyotePoint(pass)
    let facing: CGFloat = pass.variant < 0.5 ? 1 : -1
    let stopped = pass.progress >= 0.4 && pass.progress < 0.6
    let colour = moment.palette.middle.lit(-0.22).mixed(
      with: ViewColour(0x8A6A4A), by: moment.look.isDark ? 0.1 : 0.4)
    let gait = stopped ? 0 : CGFloat(sin(moment.now * 9))
    for (dx, phase) in [(-1.1, 1.0), (1.0, -1.0)] as [(CGFloat, CGFloat)] {
      var leg = Path()
      leg.move(to: CGPoint(x: feet.x + dx * facing, y: feet.y - 1.4))
      leg.addLine(to: CGPoint(x: feet.x + (dx + gait * phase * 0.4) * facing, y: feet.y))
      context.stroke(leg, with: .color(colour.color()), lineWidth: 0.3)
    }
    context.fill(
      Path(ellipseIn: CGRect(x: feet.x - 1.6, y: feet.y - 2.4, width: 3.2, height: 1.3)),
      with: .color(colour.color()))
    var tail = Path()
    tail.move(to: CGPoint(x: feet.x - 1.4 * facing, y: feet.y - 2))
    tail.addQuadCurve(
      to: CGPoint(x: feet.x - 2.8 * facing, y: feet.y - 0.8),
      control: CGPoint(x: feet.x - 2.6 * facing, y: feet.y - 2))
    context.stroke(tail, with: .color(colour.color()), lineWidth: 0.45)
    let head =
      stopped
      ? CGPoint(x: feet.x + 1.7 * facing, y: feet.y - 3.9)
      : CGPoint(x: feet.x + 2 * facing, y: feet.y - 2.8)
    var skull = Path()
    skull.move(to: CGPoint(x: head.x - 0.6 * facing, y: head.y - 0.5))
    skull.addLine(
      to: CGPoint(x: head.x + (stopped ? 0.6 : 1.1) * facing, y: head.y - (stopped ? 1 : 0)))
    skull.addLine(to: CGPoint(x: head.x - 0.4 * facing, y: head.y + 0.5))
    skull.closeSubpath()
    context.fill(skull, with: .color(colour.color()))
    var neck = Path()
    neck.move(to: CGPoint(x: feet.x + 1 * facing, y: feet.y - 2.2))
    neck.addLine(to: head)
    context.stroke(neck, with: .color(colour.color()), lineWidth: 0.6)
    var ear = Path()
    ear.move(to: CGPoint(x: head.x - 0.5 * facing, y: head.y - 0.4))
    ear.addLine(to: CGPoint(x: head.x - 0.3 * facing, y: head.y - 1.3))
    ear.addLine(to: CGPoint(x: head.x, y: head.y - 0.4))
    ear.closeSubpath()
    context.fill(ear, with: .color(colour.color()))
  }

  private func campfire(_ context: GraphicsContext, moment: ViewMoment) {
    let fire = Self.fire
    let t = moment.now
    let raining = moment.look.weather == .rain
    let glow = moment.look.isDark ? 1.0 : 0.4
    let flicker = 0.85 + 0.1 * sin(t * 7.3) + 0.05 * sin(t * 17.1)
    ViewKit.glow(
      context, CGPoint(x: fire.x, y: fire.y - 1), raining ? 4 : 12, ViewColour(0xFF9A4A),
      (raining ? 0.25 : 0.45) * glow * flicker)
    guard !raining else {
      ViewKit.circle(context, fire, 0.6, ViewColour(0xFF6A2A), 0.7)
      return
    }
    let tongues: [(dx: CGFloat, height: CGFloat, hex: UInt32)] = [
      (-0.7, 2.6, 0xFF6A2A), (0.6, 2.9, 0xFF8A3D), (0, 3.8, 0xFFB84A), (0.1, 2.2, 0xFFE08A),
    ]
    for (index, tongue) in tongues.enumerated() {
      let lick = CGFloat(0.75 + 0.25 * sin(t * (6 + Double(index) * 1.7) + Double(index)))
      let lean = CGFloat(sin(t * 3.1 + Double(index) * 2)) * 0.4
      let width: CGFloat = index == 3 ? 0.7 : 1.1
      let base = CGPoint(x: fire.x + tongue.dx, y: fire.y)
      let tip = CGPoint(x: base.x + lean, y: base.y - tongue.height * lick)
      var flame = Path()
      flame.move(to: CGPoint(x: base.x - width, y: base.y))
      flame.addQuadCurve(
        to: tip, control: CGPoint(x: base.x - width, y: base.y - tongue.height * 0.5))
      flame.addQuadCurve(
        to: CGPoint(x: base.x + width, y: base.y),
        control: CGPoint(x: base.x + width, y: base.y - tongue.height * 0.5))
      flame.closeSubpath()
      context.fill(flame, with: .color(ViewColour(tongue.hex).color(0.9)))
    }
    for index in 0..<6 {
      let period = 1.8 + 1.4 * ViewRhythm.hash(index, seed: 1361)
      let cycle = t / period + ViewRhythm.hash(index, seed: 1362)
      let p = cycle - cycle.rounded(.down)
      let drift = CGFloat(sin(t * 1.3 + Double(index) * 2)) * 1.2 * CGFloat(p)
      let spark = CGPoint(x: fire.x + drift, y: fire.y - 2 - 9 * CGFloat(p))
      ViewKit.circle(context, spark, 0.16, ViewColour(0xFFD08A), 0.9 * (1 - p))
    }
  }

  static func tumbleweedPoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    let p = CGFloat(pass.progress)
    let x = pass.variant < 0.5 ? -15 + 130 * p : 115 - 130 * p
    let bounce = abs(sin(p * .pi * 6)) * 2.2
    return CGPoint(x: x, y: 55.4 - bounce)
  }

  private func tumbleweed(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.weather == .clear || moment.look.weather == .fog,
      let pass = Self.tumbleweed.pass(at: moment.now)
    else { return }
    let point = Self.tumbleweedPoint(pass)
    let roll = (pass.variant < 0.5 ? 1 : -1) * pass.progress * 14
    let colour = moment.palette.near.lit(moment.look.isDark ? 0.12 : 0.2).mixed(
      with: ViewColour(0xA88A5A), by: moment.look.isDark ? 0.1 : 0.35)
    var weed = context
    weed.translateBy(x: point.x, y: point.y)
    weed.rotate(by: .radians(roll))
    for index in 0..<4 {
      var loop = weed
      loop.rotate(by: .degrees(Double(index) * 45))
      loop.stroke(
        Path(ellipseIn: CGRect(x: -2, y: -1.1, width: 4, height: 2.2)),
        with: .color(colour.color(0.85)), lineWidth: 0.18)
    }
    weed.stroke(
      Path(ellipseIn: CGRect(x: -1.9, y: -1.9, width: 3.8, height: 3.8)),
      with: .color(colour.color(0.7)), lineWidth: 0.16)
    context.fill(
      Path(ellipseIn: CGRect(x: point.x - 1.8, y: 57.4, width: 3.6, height: 0.6)),
      with: .color(moment.palette.near.lit(-0.3).color(0.35)))
  }

  func headlight(at now: Double) -> ViewHeadlight? { nil }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if let star = Self.shooting.interest(at: moment) { return star }
    if let pass = Self.coyote.pass(at: moment.now) {
      let point = Self.coyotePoint(pass)
      if point.x > 0, point.x < 100 {
        return ViewInterest(point: point, plane: .middle, paw: false, id: pass.index)
      }
    }
    if moment.look.weather == .clear || moment.look.weather == .fog,
      let pass = Self.tumbleweed.pass(at: moment.now)
    {
      let point = Self.tumbleweedPoint(pass)
      if point.x > 0, point.x < 100 {
        return ViewInterest(point: point, plane: .near, paw: false, id: pass.index)
      }
    }
    if let pass = Self.farCar.pass(at: moment.now) {
      let x = Self.carX(pass)
      if x > 0, x < 100 {
        return ViewInterest(
          point: CGPoint(x: x, y: Self.road), plane: .middle, paw: false, id: pass.index)
      }
    }
    return nil
  }
}
