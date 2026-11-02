import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// A road across a view with cars passing both ways now and then, their beams reaching ahead and
/// washing the house fronts. The room's own headlight sweep follows the same cars.
struct ViewRoad: Sendable {
  /// The line the cars' wheels run on, in stage units.
  var line: CGFloat
  /// The kerb, for where the beams' wash lands on the houses behind it.
  var kerb: CGFloat
  var cars: ViewRhythm
  var length: CGFloat = 13
  /// Body colours, picked per car.
  var bodies: [UInt32] = [0x5A2430, 0x23324A, 0x3A3A40, 0x6A6A70]

  func carX(_ pass: ViewRhythm.Pass) -> CGFloat {
    let progress = CGFloat(pass.progress)
    return pass.variant < 0.5 ? -48 + 196 * progress : 148 - 196 * progress
  }

  func draw(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = cars.pass(at: moment.now) else { return }
    let leftToRight = pass.variant < 0.5
    let x = carX(pass)
    let body = moment.palette.street.lit(-0.3).mixed(
      with: ViewColour(bodies[Int(pass.variant * 7) % bodies.count]), by: 0.4)
    let lit = moment.palette.lampsOn
    let nose = leftToRight ? x + length / 2 : x - length / 2
    let tail = leftToRight ? x - length / 2 : x + length / 2
    let lamp = line - 2.7
    if lit {
      let reach: CGFloat = leftToRight ? 30 : -30
      var beam = Path()
      beam.move(to: CGPoint(x: nose, y: lamp - 0.5))
      beam.addLine(to: CGPoint(x: nose + reach, y: lamp - 3.4))
      beam.addLine(to: CGPoint(x: nose + reach, y: lamp + 3.7))
      beam.addLine(to: CGPoint(x: nose, y: lamp + 0.5))
      beam.closeSubpath()
      context.fill(
        beam,
        with: .linearGradient(
          Gradient(colors: [ViewPalette.lampCore.color(0.5), ViewPalette.lampCore.color(0)]),
          startPoint: CGPoint(x: nose, y: lamp), endPoint: CGPoint(x: nose + reach, y: lamp)))
      ViewKit.glow(
        context, CGPoint(x: nose + reach * 0.7, y: kerb - 6), 9, ViewPalette.lampCore, 0.16)
    }
    ViewKit.car(
      context, x: x - length / 2, base: line, length: length, body: body,
      facingLeft: !leftToRight)
    if lit {
      ViewKit.circle(context, CGPoint(x: nose, y: lamp), 0.5, ViewPalette.lampCore)
      ViewKit.glow(context, CGPoint(x: nose, y: lamp), 2.6, ViewPalette.lampCore, 0.7)
      ViewKit.glow(context, CGPoint(x: tail, y: lamp), 1.8, ViewColour(0xFF3B3B), 0.75)
    }
  }

  func headlight(at now: Double) -> ViewHeadlight? {
    guard let pass = cars.pass(at: now) else { return nil }
    return ViewHeadlight(progress: pass.progress, leftToRight: pass.variant < 0.5)
  }

  /// The car while it is in sight through the window.
  func interest(at now: Double) -> ViewInterest? {
    guard let pass = cars.pass(at: now) else { return nil }
    let x = carX(pass)
    guard x > -5, x < 105 else { return nil }
    return ViewInterest(
      point: CGPoint(x: x, y: line - 2), plane: .street, paw: false, id: pass.index)
  }
}

/// A street lamp's head, its cone and pool of light, its shine on a wet road, and a moth around
/// it that never flies the same loop twice.
struct ViewStreetLamp: Sendable {
  var head: CGPoint
  /// Where the light lands.
  var ground: CGFloat
  /// Other lights whose shine runs down a wet road: porch lights, shop windows.
  var shines: [CGFloat] = []
  var colour = ViewPalette.lamp

  func draw(_ context: GraphicsContext, moment: ViewMoment) {
    let level = moment.lamps
    context.fill(
      Path(
        roundedRect: CGRect(x: head.x - 1.8, y: head.y - 0.6, width: 3.6, height: 1.3),
        cornerRadius: 0.6),
      with: .color((level > 0.5 ? ViewPalette.lampCore : moment.palette.street.lit(0.1)).color()))
    guard level > 0 else { return }
    var cone = Path()
    cone.move(to: CGPoint(x: head.x - 1.4, y: head.y + 0.5))
    cone.addLine(to: CGPoint(x: head.x - 10, y: ground + 4))
    cone.addLine(to: CGPoint(x: head.x + 10, y: ground + 4))
    cone.addLine(to: CGPoint(x: head.x + 1.4, y: head.y + 0.5))
    cone.closeSubpath()
    let thick = moment.look.weather != .clear
    context.fill(
      cone,
      with: .linearGradient(
        Gradient(colors: [
          colour.color((thick ? 0.42 : 0.3) * level), colour.color(0.03 * level),
        ]),
        startPoint: head, endPoint: CGPoint(x: head.x, y: ground + 4)))
    ViewKit.glow(context, head, thick ? 9 : 6, colour, 0.55 * level)
    context.fill(
      Path(ellipseIn: CGRect(x: head.x - 11, y: ground - 0.6, width: 22, height: 3.4)),
      with: .radialGradient(
        Gradient(colors: [colour.color(0.32 * level), colour.color(0)]),
        center: CGPoint(x: head.x, y: ground + 1), startRadius: 0, endRadius: 11))
    if moment.look.weather == .rain {
      for (x, alpha) in [(head.x, 0.35)] + shines.map({ ($0, 0.2) }) {
        context.fill(
          Path(CGRect(x: x - 0.9, y: ground + 2, width: 1.8, height: 9)),
          with: .linearGradient(
            Gradient(colors: [colour.color(alpha * level), colour.color(0)]),
            startPoint: CGPoint(x: x, y: ground + 2), endPoint: CGPoint(x: x, y: ground + 11)))
      }
    }
    moth(context, moment: moment)
  }

  private func moth(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.lamps > 0.5, moment.look.weather != .snow, moment.look.weather != .rain else {
      return
    }
    let t = moment.now
    let x = head.x + 2.4 * sin(t * 2.3) + 1.1 * sin(t * 5.9 + 1) + 0.5 * sin(t * 11.3)
    let y = head.y + 2.2 + 1.2 * cos(t * 3.1) + 0.7 * sin(t * 7.3 + 2)
    let flap = 0.25 + 0.15 * abs(sin(t * 31))
    ViewKit.circle(context, CGPoint(x: x, y: y), flap, ViewPalette.lampCore, 0.85)
  }
}

/// A string of bulbs hung between two points: warm fairy lights that breathe, or Christmas
/// lights in colours that chase along the string now and then.
struct ViewLightString: Sendable {
  var from: CGPoint
  var to: CGPoint
  var sag: CGFloat = 0.9
  var count = 12
  var colours: [ViewColour] = [ViewPalette.lampCore, ViewColour(0xFFB27A)]
  /// Whether the bulbs chase along the string in waves rather than breathe.
  var chases = false
  var seed = 0

  static let christmas = [0xFF4D5E, 0x3DDC84, 0xFFD166, 0x5BA8FF, 0xFF8A3D].map(ViewColour.init)

  func draw(_ context: GraphicsContext, moment: ViewMoment) {
    ViewKit.wire(
      context, from: from, to: to, sag: sag, colour: moment.palette.street.lit(-0.3), width: 0.15)
    let lamps = moment.lamps
    guard lamps > 0 else { return }
    for index in 0..<count {
      let point = ViewKit.onWire(
        from: from, to: to, sag: sag, share: (CGFloat(index) + 0.5) / CGFloat(count))
      let level: Double
      if chases {
        // A wave runs along the string every so often; between waves the bulbs glow steady.
        let wave = (moment.now * 0.35 + Double(seed)).truncatingRemainder(dividingBy: 1)
        let head = wave * Double(count + 6) - 3
        let near = abs(Double(index) - head)
        level = near < 2 ? 1 : 0.7
      } else {
        level =
          0.75 + 0.25
          * sin(moment.now * (0.9 + 0.5 * ViewRhythm.hash(index + seed, seed: 51)) + Double(index))
      }
      let colour = colours[(index + seed) % colours.count]
      let bulb = CGPoint(x: point.x, y: point.y + 0.4)
      ViewKit.circle(context, bulb, 0.3, colour, lamps)
      ViewKit.glow(context, bulb, 1.6, colour, 0.45 * level * lamps)
    }
  }
}

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

  func draw(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = rhythm.pass(at: moment.now) else { return }
    let (point, sitting, facing) = pose(pass)
    let colour = moment.palette.colour(plane).lit(-0.45).color()
    var shape = context
    shape.translateBy(x: point.x, y: point.y)
    shape.scaleBy(x: facing * 0.42, y: 0.42)
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

/// A leafy branch reaching in from a corner, swaying in the wind, with snow on some leaves.
struct ViewBranch: Sendable {
  var anchor = CGPoint(x: 116, y: -10)
  var scale: CGFloat = 1.3
  /// 1 reaches in from the right, -1 from the left.
  var side: CGFloat = 1
  /// Leaves tinted towards this colour, for blossom or autumn; `nil` keeps the plane's own.
  var tint: ViewColour?

  func draw(_ context: GraphicsContext, moment: ViewMoment) {
    let colour = moment.palette.near
    let leafColour =
      tint.map { colour.mixed(with: $0, by: moment.look.isDark ? 0.25 : 0.6) } ?? colour
    let wind = moment.look.weather == .rain ? 1.8 : 1
    let t = moment.now
    let sway = (0.6 * sin(t * 0.7) + 0.3 * sin(t * 1.9 + 1) + 0.15 * sin(t * 4.3)) * wind
    var branch = context
    branch.translateBy(x: anchor.x, y: anchor.y)
    branch.scaleBy(x: scale * side, y: scale)
    branch.rotate(by: .degrees(sway * 1.6))
    let twigs: [(CGPoint, CGPoint, CGPoint)] = [
      (.zero, CGPoint(x: -36, y: 13), CGPoint(x: -16, y: 1)),
      (CGPoint(x: -14, y: 3.4), CGPoint(x: -24, y: -3), CGPoint(x: -19, y: 2)),
      (CGPoint(x: -24, y: 8.2), CGPoint(x: -30, y: 17), CGPoint(x: -26, y: 13)),
      (CGPoint(x: -6, y: 1.2), CGPoint(x: -10, y: 9), CGPoint(x: -9, y: 4)),
    ]
    for (index, twig) in twigs.enumerated() {
      var stem = Path()
      stem.move(to: twig.0)
      stem.addQuadCurve(to: twig.1, control: twig.2)
      branch.stroke(stem, with: .color(colour.color()), lineWidth: index == 0 ? 1.1 : 0.5)
      for step in 1...7 {
        let share = CGFloat(step) / 7.5
        let u = 1 - share
        let point = CGPoint(
          x: u * u * twig.0.x + 2 * u * share * twig.2.x + share * share * twig.1.x,
          y: u * u * twig.0.y + 2 * u * share * twig.2.y + share * share * twig.1.y)
        for leafSide in [-1.0, 1.0] {
          let seed = index * 40 + step * 2 + (leafSide > 0 ? 1 : 0)
          let flutter = sin(t * (1.8 + ViewRhythm.hash(seed, seed: 95)) + Double(seed)) * 12 * wind
          var leaf = branch
          leaf.translateBy(x: point.x, y: point.y)
          leaf.rotate(by: .degrees(leafSide * 55 + flutter + 25 * ViewRhythm.hash(seed, seed: 96)))
          let length = 2.2 + 1.2 * CGFloat(ViewRhythm.hash(seed, seed: 97))
          leaf.fill(
            Path(ellipseIn: CGRect(x: 0, y: -length * 0.22, width: length, height: length * 0.44)),
            with: .color(leafColour.lit(seed % 3 == 0 ? 0.05 : 0).color()))
          if moment.look.weather == .snow, seed % 4 == 0 {
            leaf.fill(
              Path(
                ellipseIn: CGRect(
                  x: 0.2, y: -length * 0.3, width: length * 0.7, height: length * 0.2)),
              with: .color(ViewKit.snow(moment.look).color(0.8)))
          }
        }
      }
    }
  }
}
