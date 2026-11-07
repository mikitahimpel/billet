import CoreGraphics
import Foundation
import Pet
import SwiftUI

extension MoonlitPeaks {
  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: Self.shootingStar.draw(context, moment: moment)
    case .middle: gondola(context, moment: moment)
    case .street:
      ViewWindows.draw(Self.chaletWindows, context, moment: moment)
      smoke(context, moment: moment)
      ViewLightString(
        from: CGPoint(x: Self.chalet.minX - 2.4, y: Self.chalet.minY + 1.6),
        to: CGPoint(x: Self.chalet.maxX + 2.4, y: Self.chalet.minY + 1.6), sag: 0.7, count: 11,
        colours: [ViewPalette.lampCore, ViewColour(0xFFB27A), ViewColour(0xFF8A9A)], seed: 3
      ).draw(context, moment: moment)
      fox(context, moment: moment)
    case .near: break
    }
  }

  static func gondolaPoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    let p = CGFloat(pass.progress)
    let x = pass.variant < 0.5 ? -50 + 200 * p : 150 - 200 * p
    return CGPoint(x: x, y: cableY(x))
  }

  /// A gondola cabin gliding along the cable, swinging a little, its windows lit after dark.
  private func gondola(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = Self.gondola.pass(at: moment.now) else { return }
    let grip = Self.gondolaPoint(pass)
    let swing = CGFloat(sin(moment.now * 1.3)) * 0.35
    let body = ViewColour(0xD8443A).mixed(
      with: moment.palette.middle, by: moment.look.isDark ? 0.55 : 0.25)
    let cabin = CGRect(x: grip.x - 2.2 + swing, y: grip.y + 2.6, width: 4.4, height: 3.4)
    var hanger = Path()
    hanger.move(to: grip)
    hanger.addLine(to: CGPoint(x: cabin.midX, y: cabin.minY))
    context.stroke(hanger, with: .color(moment.palette.middle.lit(-0.3).color()), lineWidth: 0.2)
    ViewKit.rect(
      context, CGRect(x: grip.x - 0.6, y: grip.y - 0.2, width: 1.2, height: 0.6),
      moment.palette.middle.lit(-0.3))
    context.fill(Path(roundedRect: cabin, cornerRadius: 0.7), with: .color(body.color()))
    let glass = CGRect(
      x: cabin.minX + 0.5, y: cabin.minY + 0.6, width: cabin.width - 1, height: 1.3)
    let lit = moment.lamps
    ViewKit.rect(context, glass, body.lit(-0.35))
    if lit > 0 {
      ViewKit.rect(context, glass, ViewPalette.lampCore, 0.85 * lit)
      ViewKit.glow(context, CGPoint(x: cabin.midX, y: cabin.midY), 5, ViewPalette.lamp, 0.3 * lit)
    }
    ViewKit.rect(
      context, CGRect(x: cabin.minX, y: cabin.maxY - 0.5, width: cabin.width, height: 0.5),
      body.lit(-0.2))
  }

  /// Smoke curling up from the chalet's chimney, drifting off with the wind.
  private func smoke(_ context: GraphicsContext, moment: ViewMoment) {
    let colour = moment.palette.skyMiddle.lit(moment.look.isDark ? 0.18 : 0.4)
    let top = Self.chimney
    for puff in 0..<6 {
      let p = (moment.now * 0.11 + Double(puff) / 6).truncatingRemainder(dividingBy: 1)
      let rise = CGFloat(p) * 15
      let drift = CGFloat(p * p) * 8 + CGFloat(sin(moment.now * 0.5 + Double(puff))) * 0.7
      ViewKit.circle(
        context, CGPoint(x: top.x + drift, y: top.y - 1 - rise), 0.8 + CGFloat(p) * 2.2, colour,
        0.3 * (1 - p))
    }
  }

  /// Where the fox is: trotting across, stopping in the middle to sniff the snow.
  static func foxPose(_ pass: ViewRhythm.Pass) -> (point: CGPoint, facing: CGFloat, still: Bool) {
    let p = pass.progress
    let share: Double
    let still: Bool
    switch p {
    case ..<0.42:
      share = p / 0.42 * 0.5
      still = false
    case ..<0.58:
      share = 0.5
      still = true
    default:
      share = 0.5 + (p - 0.58) / 0.42 * 0.5
      still = false
    }
    let leftToRight = pass.variant < 0.5
    let x = leftToRight ? -12 + 124 * CGFloat(share) : 112 - 124 * CGFloat(share)
    return (CGPoint(x: x, y: streetBase + 2.6), leftToRight ? 1 : -1, still)
  }

  private func fox(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = Self.fox.pass(at: moment.now) else { return }
    let (point, facing, still) = Self.foxPose(pass)
    let fur = ViewColour(0xE07A3A).mixed(
      with: moment.palette.street, by: moment.look.isDark ? 0.5 : 0.15)
    let dark = fur.lit(-0.45)
    var shape = context
    shape.translateBy(x: point.x, y: point.y)
    shape.scaleBy(x: facing, y: 1)
    let trot = still ? 0 : CGFloat(sin(moment.now * 12))
    for (x, phase) in [(-1.1, trot), (-0.6, -trot), (0.7, -trot), (1.2, trot)]
      as [(CGFloat, CGFloat)]
    {
      shape.fill(
        Path(CGRect(x: x + phase * 0.25, y: -1.1, width: 0.28, height: 1.1)),
        with: .color(dark.color()))
    }
    shape.fill(
      Path(ellipseIn: CGRect(x: -1.6, y: -2.1, width: 3.4, height: 1.3)),
      with: .color(fur.color()))
    // The brush of a tail, white at the tip.
    let wag = CGFloat(sin(moment.now * 2.2)) * 0.3
    shape.fill(
      Path(ellipseIn: CGRect(x: -4, y: -2.2 + wag, width: 2.8, height: 1)),
      with: .color(fur.lit(0.04).color()))
    shape.fill(
      Path(ellipseIn: CGRect(x: -4.1, y: -2.1 + wag, width: 0.9, height: 0.8)),
      with: .color(ViewKit.snow(moment.look).color()))
    // Head low when sniffing.
    let headY: CGFloat = still ? -1.5 : -2.6
    shape.fill(
      Path(ellipseIn: CGRect(x: 1.2, y: headY, width: 1.3, height: 1.1)),
      with: .color(fur.color()))
    var snout = Path()
    snout.move(to: CGPoint(x: 2.3, y: headY + 0.3))
    snout.addLine(to: CGPoint(x: 3.2, y: headY + 0.8))
    snout.addLine(to: CGPoint(x: 2.3, y: headY + 1))
    snout.closeSubpath()
    shape.fill(snout, with: .color(fur.lit(0.08).color()))
    for x in [1.4, 2] as [CGFloat] {
      var ear = Path()
      ear.move(to: CGPoint(x: x, y: headY + 0.2))
      ear.addLine(to: CGPoint(x: x + 0.2, y: headY - 0.6))
      ear.addLine(to: CGPoint(x: x + 0.5, y: headY + 0.2))
      ear.closeSubpath()
      shape.fill(ear, with: .color(dark.color()))
    }
  }

  func headlight(at now: Double) -> ViewHeadlight? { nil }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if let star = Self.shootingStar.interest(at: moment) { return star }
    if let pass = Self.fox.pass(at: moment.now) {
      let point = Self.foxPose(pass).point
      if point.x > -5, point.x < 105 {
        return ViewInterest(
          point: CGPoint(x: point.x, y: point.y - 1.5), plane: .street, paw: false,
          id: pass.index)
      }
    }
    if let pass = Self.gondola.pass(at: moment.now) {
      let point = Self.gondolaPoint(pass)
      if point.x > 0, point.x < 100 {
        return ViewInterest(
          point: CGPoint(x: point.x, y: point.y + 4), plane: .middle, paw: false, id: pass.index)
      }
    }
    return nil
  }
}
