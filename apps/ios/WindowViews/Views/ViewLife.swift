import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// The room's own headlight sweep follows the same cars.
struct ViewRoad: Sendable {
  /// The line the cars' wheels run on, in stage units.
  var line: CGFloat
  /// The kerb, for where the beams' wash lands on the houses behind it.
  var kerb: CGFloat
  var cars: ViewRhythm
  var length: CGFloat = 13
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

struct ViewLightString: Sendable {
  var from: CGPoint
  var to: CGPoint
  var sag: CGFloat = 0.9
  var count = 12
  var colours: [ViewColour] = [ViewPalette.lampCore, ViewColour(0xFFB27A)]
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

extension ViewKit {
  /// `sway` from -1 to 1 bends the crown in the wind.
  static func palm(
    _ context: GraphicsContext, x: CGFloat, base: CGFloat, height: CGFloat, lean: CGFloat,
    colour: ViewColour, sway: Double = 0
  ) {
    let top = CGPoint(x: x + lean + CGFloat(sway) * height * 0.015, y: base - height)
    let control = CGPoint(x: x + lean * 0.2, y: base - height * 0.55)
    let width = max(height * 0.022, 0.35)
    var trunk = Path()
    trunk.move(to: CGPoint(x: x - width, y: base))
    trunk.addQuadCurve(
      to: CGPoint(x: top.x - width * 0.6, y: top.y),
      control: CGPoint(x: control.x - width, y: control.y))
    trunk.addLine(to: CGPoint(x: top.x + width * 0.6, y: top.y))
    trunk.addQuadCurve(
      to: CGPoint(x: x + width, y: base), control: CGPoint(x: control.x + width, y: control.y))
    trunk.closeSubpath()
    context.fill(trunk, with: .color(colour.color()))
    let reach = height * 0.2
    for index in 0..<9 {
      let angle = Double(index) / 8 * Double.pi + Double.pi + sway * 0.12
      palmFrond(
        context, from: top, angle: angle, length: reach * (0.8 + 0.3 * CGFloat(index % 3) / 2),
        colour: colour.lit(index % 2 == 0 ? 0 : 0.04))
    }
    circle(context, top, width * 1.8, colour.lit(-0.05))
  }

  static func palmFrond(
    _ context: GraphicsContext, from: CGPoint, angle: Double, length: CGFloat, colour: ViewColour
  ) {
    let dx = CGFloat(cos(angle))
    let dy = CGFloat(sin(angle))
    let end = CGPoint(x: from.x + dx * length, y: from.y + dy * length * 0.5 + length * 0.55)
    let control = CGPoint(
      x: from.x + dx * length * 0.6, y: from.y + dy * length * 0.6 - length * 0.12)
    var upper: [CGPoint] = []
    var lower: [CGPoint] = []
    for step in 0...10 {
      let t = CGFloat(step) / 10
      let u = 1 - t
      let point = CGPoint(
        x: u * u * from.x + 2 * u * t * control.x + t * t * end.x,
        y: u * u * from.y + 2 * u * t * control.y + t * t * end.y)
      let half = length * 0.09 * sin(.pi * min(1, t * 1.4)) * (1 - t * 0.5)
      upper.append(CGPoint(x: point.x, y: point.y - half))
      lower.append(CGPoint(x: point.x, y: point.y + half))
    }
    var blade = Path()
    blade.addLines(upper + lower.reversed())
    blade.closeSubpath()
    context.fill(blade, with: .color(colour.color()))
  }
}

/// Seeded, so it is the same every run.
enum ViewGrain {
  static let size = 64

  static let tile: CGImage? = {
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    for index in 0..<(size * size) {
      // Mostly a faint darkening, now and then a fleck of light: never more than 5 %.
      let value = ViewRhythm.hash(index, seed: 991)
      let light = ViewRhythm.hash(index, seed: 992) > 0.8
      let alpha = UInt8(value * (light ? 8 : 13))
      let shade: UInt8 = light ? alpha : 0
      pixels[index * 4] = shade
      pixels[index * 4 + 1] = shade
      pixels[index * 4 + 2] = shade
      pixels[index * 4 + 3] = alpha
    }
    return pixels.withUnsafeMutableBytes { buffer in
      CGContext(
        data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }
  }()
}

/// Each leaf on its own clock, so they never fall together. None in snow.
struct ViewLeaves: Sendable {
  var count = 5
  /// Where leaves start and how far they fall, in stage units.
  var area = CGRect(x: -10, y: -6, width: 120, height: 62)
  var seed = 0
  var colours: [UInt32] = [0xD8843A, 0xC0503A, 0xE0B04A, 0x8A9A4A]

  func draw(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.weather != .snow else { return }
    let wind = moment.look.weather == .rain ? 1.8 : 1
    for index in 0..<count {
      let id = seed * 50 + index
      let period = 11 + 9 * ViewRhythm.hash(id, seed: 961)
      let offset = ViewRhythm.hash(id, seed: 962)
      let cycle = moment.now / period + offset
      let p = cycle - cycle.rounded(.down)
      // Only part of each cycle has a leaf in the air.
      guard p < 0.55 else { continue }
      let fall = p / 0.55
      let lane = ViewRhythm.hash(id &+ Int(cycle.rounded(.down)) % 997, seed: 963)
      let x =
        area.minX + area.width * CGFloat(lane) + CGFloat(fall * 14 * wind)
        + CGFloat(2.4 * sin(moment.now * 1.7 + Double(index) * 3))
      let y = area.minY + area.height * CGFloat(fall)
      let colour = ViewColour(colours[id % colours.count]).mixed(
        with: moment.palette.near, by: moment.look.isDark ? 0.6 : 0.25)
      var leaf = context
      leaf.translateBy(x: x, y: y)
      leaf.rotate(by: .radians(moment.now * (2 + Double(index % 3)) + Double(index)))
      leaf.scaleBy(x: 1, y: CGFloat(0.35 + 0.65 * abs(sin(moment.now * 3 + Double(index)))))
      leaf.fill(
        Path(ellipseIn: CGRect(x: -0.9, y: -0.4, width: 1.8, height: 0.8)),
        with: .color(colour.color(0.9)))
    }
  }
}

struct ViewFireflies: Sendable {
  var count: Int
  var area: CGRect
  var seed = 0

  func draw(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.hour == .dusk || moment.look.hour == .night, moment.look.weather != .rain,
      moment.look.weather != .snow
    else { return }
    let colour = ViewColour(0xD9FF7A)
    for index in 0..<count {
      let id = seed * 100 + index
      let a = ViewRhythm.hash(id, seed: 451)
      let b = ViewRhythm.hash(id, seed: 452)
      let t = moment.now
      let x =
        area.minX + area.width * CGFloat(a)
        + CGFloat(3 * sin(t * (0.15 + 0.1 * b) + a * 9) + 1.2 * sin(t * 0.7 + b * 5))
      let y =
        area.minY + area.height * CGFloat(b)
        + CGFloat(2 * cos(t * (0.12 + 0.1 * a) + b * 7) + 0.8 * sin(t * 0.9 + a * 3))
      let blink = sin(t * (0.5 + 0.4 * a) + b * 20)
      guard blink > 0.55 else { continue }
      let level = (blink - 0.55) / 0.45
      ViewKit.glow(context, CGPoint(x: x, y: y), 3, colour, 0.7 * level)
      ViewKit.circle(context, CGPoint(x: x, y: y), 0.35, colour, level)
    }
  }
}
