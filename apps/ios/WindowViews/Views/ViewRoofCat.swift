import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// Now and then a cat climbs a roof, sits a while at the ridge, and goes down the far side.
struct ViewRoofCat: Sendable {
  var rhythm: ViewRhythm
  var left: CGPoint
  var ridge: CGPoint
  var right: CGPoint
  var plane = ViewPlane.middle

  /// Where the cat is: walking up for the first fifth, sitting at the ridge, then walking down
  /// the far side for the last fifth. `facing` is 1 for right and -1 for left.
  func pose(_ pass: ViewRhythm.Pass) -> (CGPoint, sitting: Bool, facing: CGFloat) {
    let fromLeft = pass.variant < 0.5
    let (start, end) = fromLeft ? (left, right) : (right, left)
    let facing: CGFloat = fromLeft ? 1 : -1
    let p = CGFloat(pass.progress)
    func along(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
      CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
    switch p {
    case ..<0.2: return (along(start, ridge, p / 0.2), false, facing)
    case ..<0.8: return (ridge, true, facing)
    default: return (along(ridge, end, (p - 0.8) / 0.2), false, facing)
    }
  }

  /// Watched while it climbs and leaves, not for the whole of its sit.
  func interest(at now: Double) -> ViewInterest? {
    guard let pass = rhythm.pass(at: now), pass.progress < 0.3 || pass.progress > 0.8 else {
      return nil
    }
    return ViewInterest(point: pose(pass).0, plane: plane, paw: false, id: pass.index)
  }

  /// How big the cat is drawn: small far off on a roof, bigger on a near fence.
  var size: CGFloat = 0.42

  /// `eyeShine` from 0 to 1 lights the sitting cat's eyes, as a car's lights catch them.
  func draw(_ context: GraphicsContext, moment: ViewMoment, eyeShine: Double = 0) {
    guard let pass = rhythm.pass(at: moment.now) else { return }
    let (point, sitting, facing) = pose(pass)
    let colour = moment.palette.colour(plane).lit(-0.45).color()
    var shape = context
    shape.translateBy(x: point.x, y: point.y)
    shape.scaleBy(x: facing * size, y: size)
    if sitting {
      shape.fill(
        Path(ellipseIn: CGRect(x: -1.6, y: -4.2, width: 3.2, height: 4.2)), with: .color(colour))
      shape.fill(
        Path(ellipseIn: CGRect(x: -1.4, y: -6.4, width: 2.8, height: 2.6)), with: .color(colour))
      for side in [-1.0, 1.0] as [CGFloat] {
        var ear = Path()
        ear.move(to: CGPoint(x: side * 1.2, y: -5.6))
        ear.addLine(to: CGPoint(x: side * 1.0, y: -7.3))
        ear.addLine(to: CGPoint(x: side * 0.3, y: -6.2))
        ear.closeSubpath()
        shape.fill(ear, with: .color(colour))
      }
      var tail = Path()
      let swish = sin(moment.now * 1.3) * 1.2
      tail.move(to: CGPoint(x: -1.2, y: -0.4))
      tail.addQuadCurve(to: CGPoint(x: -3.6, y: -2.2 + swish), control: CGPoint(x: -3.8, y: 0.2))
      shape.stroke(tail, with: .color(colour), lineWidth: 0.7)
      // Eyes: a slow blink, and a green-gold shine when light catches them.
      let blink = (moment.now / 5.3).truncatingRemainder(dividingBy: 1) > 0.97
      if eyeShine > 0.05, !blink {
        for side in [-0.55, 0.55] as [CGFloat] {
          let eye = CGPoint(x: side, y: -5.3)
          ViewKit.glow(shape, eye, 0.9, ViewColour(0xC8FF7A), 0.6 * eyeShine)
          shape.fill(
            Path(ellipseIn: CGRect(x: eye.x - 0.28, y: eye.y - 0.2, width: 0.56, height: 0.4)),
            with: .color(ViewColour(0xE8FFB0).color(eyeShine)))
        }
      }
    } else {
      let step = sin(moment.now * 9) * 0.5
      shape.fill(
        Path(ellipseIn: CGRect(x: -2.6, y: -3.6, width: 5.2, height: 2.4)), with: .color(colour))
      shape.fill(
        Path(ellipseIn: CGRect(x: 1.8, y: -5, width: 2.4, height: 2.2)), with: .color(colour))
      var ear = Path()
      ear.move(to: CGPoint(x: 2.6, y: -4.6))
      ear.addLine(to: CGPoint(x: 3, y: -5.9))
      ear.addLine(to: CGPoint(x: 3.6, y: -4.6))
      shape.fill(ear, with: .color(colour))
      for (x, phase) in [(-1.8, step), (1.6, -step)] as [(CGFloat, CGFloat)] {
        shape.fill(
          Path(CGRect(x: x + phase, y: -1.6, width: 0.6, height: 1.6)), with: .color(colour))
      }
      var tail = Path()
      tail.move(to: CGPoint(x: -2.4, y: -2.8))
      tail.addQuadCurve(to: CGPoint(x: -4.4, y: -5.6), control: CGPoint(x: -4.6, y: -2.6))
      shape.stroke(tail, with: .color(colour), lineWidth: 0.7)
    }
  }
}
