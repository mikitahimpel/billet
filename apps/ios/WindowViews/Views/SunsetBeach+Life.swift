import CoreGraphics
import Foundation
import Pet
import SwiftUI

extension SunsetBeach {
  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far:
      sunAndGlitter(context, moment: moment)
      sailboat(context, moment: moment)
    case .middle:
      lighthouseBeam(context, moment: moment)
      for lamp in Self.pierLamps {
        ViewKit.circle(
          context, lamp, 0.45,
          moment.lamps > 0.5 ? ViewPalette.lampCore : moment.palette.middle.lit(0.1))
        ViewKit.glow(context, lamp, 4, ViewPalette.lamp, 0.5 * moment.lamps)
        ViewKit.rect(
          context, CGRect(x: lamp.x - 0.6, y: Self.horizon + 7, width: 1.2, height: 4),
          ViewPalette.lamp, 0.25 * moment.lamps)
      }
      gulls(context, moment: moment)
    case .street:
      waves(context, moment: moment)
      ViewKit.litWindow(context, Self.shackWindow, level: moment.lamps)
      ViewLightString(
        from: CGPoint(x: Self.shack.maxX + 1.6, y: Self.shack.minY + 0.4),
        to: CGPoint(x: Self.tower.minX - 0.6, y: Self.tower.minY - 0.4), sag: 1.8, count: 14,
        colours: [ViewColour(0xFFD166), ViewColour(0xFF8A5B), ViewColour(0x7AE0C0)], seed: 3
      ).draw(context, moment: moment)
      flag(context, moment: moment)
      Self.walker.draw(context, moment: moment)
    case .near:
      dunegrass(context, moment: moment)
    }
  }

  /// From about -1 to 1, never quite repeating.
  static func breeze(_ moment: ViewMoment) -> Double {
    let t = moment.now
    let wind = moment.look.weather == .rain ? 1.8 : 1
    return (0.55 * sin(t * 0.6) + 0.3 * sin(t * 1.7 + 1) + 0.15 * sin(t * 3.7)) * wind
  }

  private func sunAndGlitter(_ context: GraphicsContext, moment: ViewMoment) {
    let look = moment.look
    guard look.weather != .rain, look.weather != .snow else { return }
    let alpha = look.weather == .fog ? 0.35 : 1.0
    let source: CGPoint
    let colour: ViewColour
    switch look.hour {
    case .dusk, .morning:
      source = Self.sun
      colour = ViewColour(0xFFB86A)
    case .night:
      source = CGPoint(x: moon.x, y: Self.horizon)
      colour = ViewColour(0xDDE6FF)
    case .day: return
    }
    if look.hour != .night {
      ViewKit.glow(context, Self.sun, 24, colour, 0.35 * alpha)
      var sky = context
      sky.clip(to: Path(CGRect(x: -45, y: -50, width: 190, height: Self.horizon + 50)))
      ViewKit.circle(sky, Self.sun, 5, ViewColour(0xFFD9A0), 0.95 * alpha)
    }
    for index in 0..<18 {
      let share = CGFloat(index) / 17
      let y = Self.horizon + 0.6 + share * share * 13
      let spread = 1.5 + share * 9
      let jitter = CGFloat(ViewRhythm.hash(index, seed: 831)) - 0.5
      let x =
        source.x + jitter * 2 * spread + CGFloat(sin(moment.now * 0.8 + Double(index) * 1.7)) * 0.8
      let speed = 1.5 + 2 * ViewRhythm.hash(index, seed: 832)
      let shimmer = 0.5 + 0.5 * sin(moment.now * speed + Double(index))
      let width = 1.2 + share * 3.5
      ViewKit.rect(
        context, CGRect(x: x - width / 2, y: y, width: width, height: 0.22 + share * 0.2), colour,
        0.75 * shimmer * alpha)
    }
  }

  static func boatPoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    let p = CGFloat(pass.progress)
    let x = pass.variant < 0.5 ? -15 + 130 * p : 115 - 130 * p
    return CGPoint(x: x, y: horizon + 1.4)
  }

  private func sailboat(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = Self.boat.pass(at: moment.now) else { return }
    let point = Self.boatPoint(pass)
    let facing: CGFloat = pass.variant < 0.5 ? 1 : -1
    let bob = CGFloat(sin(moment.now * 1.4)) * 0.15
    let hullColour = moment.palette.far.lit(-0.4)
    var hull = Path()
    hull.move(to: CGPoint(x: point.x - 2.4 * facing, y: point.y - 0.8 + bob))
    hull.addLine(to: CGPoint(x: point.x + 2.6 * facing, y: point.y - 0.8 + bob))
    hull.addLine(to: CGPoint(x: point.x + 1.8 * facing, y: point.y + bob))
    hull.addLine(to: CGPoint(x: point.x - 1.8 * facing, y: point.y + bob))
    hull.closeSubpath()
    context.fill(hull, with: .color(hullColour.color()))
    let sail = ViewColour(0xF4E6D8).mixed(
      with: moment.palette.far, by: moment.look.isDark ? 0.55 : 0.2)
    var main = Path()
    main.move(to: CGPoint(x: point.x - 0.1 * facing, y: point.y - 1.1 + bob))
    main.addLine(to: CGPoint(x: point.x - 0.1 * facing, y: point.y - 6.4 + bob))
    main.addLine(to: CGPoint(x: point.x - 2.3 * facing, y: point.y - 1.1 + bob))
    main.closeSubpath()
    context.fill(main, with: .color(sail.color()))
    var jib = Path()
    jib.move(to: CGPoint(x: point.x + 0.2 * facing, y: point.y - 1.1 + bob))
    jib.addLine(to: CGPoint(x: point.x + 0.2 * facing, y: point.y - 5.4 + bob))
    jib.addLine(to: CGPoint(x: point.x + 2.2 * facing, y: point.y - 1.1 + bob))
    jib.closeSubpath()
    context.fill(jib, with: .color(sail.lit(-0.08).color()))
    if moment.look.isDark {
      let top = CGPoint(x: point.x - 0.1 * facing, y: point.y - 6.6 + bob)
      ViewKit.circle(context, top, 0.2, ViewPalette.lampCore)
      ViewKit.glow(context, top, 1.4, ViewPalette.lampCore, 0.5)
    }
  }

  private func lighthouseBeam(_ context: GraphicsContext, moment: ViewMoment) {
    let lamp = Self.lighthouse
    let level = moment.lamps
    ViewKit.rect(
      context, CGRect(x: lamp.x - 0.7, y: lamp.y - 0.6, width: 1.4, height: 1.4),
      level > 0.5 ? ViewPalette.lampCore : moment.palette.middle.lit(0.15))
    guard level > 0 else { return }
    let angle = moment.now * 0.9
    let reach = CGFloat(sin(angle)) * 70
    let facing = cos(angle)
    let thick = moment.look.weather == .clear ? 1.0 : 1.5
    var beam = Path()
    beam.move(to: CGPoint(x: lamp.x, y: lamp.y - 0.4))
    beam.addLine(to: CGPoint(x: lamp.x + reach, y: lamp.y - 3.4))
    beam.addLine(to: CGPoint(x: lamp.x + reach, y: lamp.y + 3))
    beam.addLine(to: CGPoint(x: lamp.x, y: lamp.y + 0.4))
    beam.closeSubpath()
    context.fill(
      beam,
      with: .linearGradient(
        Gradient(colors: [
          ViewPalette.lampCore.color(0.35 * level * thick * abs(sin(angle))),
          ViewPalette.lampCore.color(0),
        ]), startPoint: lamp, endPoint: CGPoint(x: lamp.x + reach, y: lamp.y)))
    let flash = max(0, facing - 0.8) / 0.2
    ViewKit.glow(
      context, lamp, 3 + 6 * CGFloat(flash), ViewPalette.lampCore, (0.4 + 0.5 * flash) * level)
  }

  static func gullPoint(_ pass: ViewRhythm.Pass, bird: Int, now: Double) -> CGPoint {
    let p = CGFloat(pass.progress)
    let lag = CGFloat(bird) * 0.06
    let share = max(0, p - lag) * 1.2
    let x = pass.variant < 0.5 ? -15 + 135 * share : 115 - 135 * share
    let y =
      6 + 8 * CGFloat(pass.variant) + CGFloat(bird) * 2.2
      + CGFloat(sin(now * 0.7 + Double(bird) * 2)) * 1.4
    return CGPoint(x: x, y: y)
  }

  private func gulls(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.hour != .night, moment.look.weather != .snow,
      let pass = Self.gulls.pass(at: moment.now)
    else { return }
    let colour = ViewColour(0xF4F1EA).mixed(
      with: moment.palette.middle, by: moment.look.isDark ? 0.5 : 0.15)
    for bird in 0..<3 {
      let point = Self.gullPoint(pass, bird: bird, now: moment.now)
      let beat = sin(moment.now * 5 + Double(bird) * 2)
      let lift = CGFloat(beat > 0.6 ? (beat - 0.6) * 2 : 0) + 0.25
      var wings = Path()
      wings.move(to: CGPoint(x: point.x - 1.6, y: point.y - lift))
      wings.addQuadCurve(to: point, control: CGPoint(x: point.x - 0.8, y: point.y - lift - 0.6))
      wings.addQuadCurve(
        to: CGPoint(x: point.x + 1.6, y: point.y - lift),
        control: CGPoint(x: point.x + 0.8, y: point.y - lift - 0.6))
      context.stroke(wings, with: .color(colour.color()), lineWidth: 0.3)
    }
  }

  private func waves(_ context: GraphicsContext, moment: ViewMoment) {
    let palette = moment.palette
    let dark = moment.look.isDark
    let foam = ViewColour(0xFFF6EC).mixed(with: palette.far, by: dark ? 0.55 : 0.15)
    let water = palette.far.lit(dark ? 0.04 : 0.1)
    let period = moment.look.weather == .rain ? 5.5 : 7.5
    let base = Self.shore
    let swell = 0.5 + 0.5 * sin(moment.now * 2 * .pi / period)
    var breaker = Path()
    breaker.move(to: CGPoint(x: -45, y: 38.6))
    var x: CGFloat = -45
    while x < 145 {
      let wobble = CGFloat(sin(Double(x) * 0.21 + moment.now * 0.5)) * 0.3
      breaker.addQuadCurve(
        to: CGPoint(x: x + 12, y: 38.6 + wobble), control: CGPoint(x: x + 6, y: 38.2 - wobble))
      x += 12
    }
    context.stroke(breaker, with: .color(foam.color(0.25 + 0.3 * swell)), lineWidth: 0.35)
    for wave in 0..<3 {
      let cycle = moment.now / period + Double(wave) / 3
      let phase = cycle - cycle.rounded(.down)
      let reach = sin(phase * .pi)
      let y = 40.6 + CGFloat(reach) * 6.2 + CGFloat(wave) * 0.3
      let alpha = phase < 0.5 ? 0.85 : 0.85 * (1 - (phase - 0.5) * 2)
      if y > base {
        context.fill(
          Path(CGRect(x: -45, y: base, width: 190, height: y - base)),
          with: .color(water.color(0.3 * alpha)))
      }
      var line = Path()
      line.move(to: CGPoint(x: -45, y: y))
      var segment: CGFloat = -45
      while segment < 145 {
        let wobble = CGFloat(sin(Double(segment) * 0.13 + moment.now * 0.6 + Double(wave) * 2))
        line.addQuadCurve(
          to: CGPoint(x: segment + 10, y: y + wobble * 0.5),
          control: CGPoint(x: segment + 5, y: y - 0.5 + wobble * 0.3))
        segment += 10
      }
      context.stroke(line, with: .color(foam.color(alpha)), lineWidth: 0.45)
    }
  }

  private func flag(_ context: GraphicsContext, moment: ViewMoment) {
    let top = Self.flag
    let flutter = CGFloat(sin(moment.now * 6)) * 0.4
    let lift = CGFloat(Self.breeze(moment)) * 0.4
    var cloth = Path()
    cloth.move(to: top)
    cloth.addQuadCurve(
      to: CGPoint(x: top.x + 3.2, y: top.y + 0.8 - lift),
      control: CGPoint(x: top.x + 1.6, y: top.y + flutter))
    cloth.addLine(to: CGPoint(x: top.x + 3.2, y: top.y + 2.2 - lift))
    cloth.addQuadCurve(
      to: CGPoint(x: top.x, y: top.y + 1.8),
      control: CGPoint(x: top.x + 1.6, y: top.y + 2 + flutter))
    cloth.closeSubpath()
    context.fill(
      cloth,
      with: .color(
        ViewColour(0xE5503A).mixed(with: moment.palette.street, by: moment.look.isDark ? 0.5 : 0.15)
          .color()))
  }

  private func dunegrass(_ context: GraphicsContext, moment: ViewMoment) {
    let sway = Self.breeze(moment)
    let colour = moment.palette.near.mixed(
      with: ViewColour(0x9AA86A), by: moment.look.isDark ? 0.12 : 0.35)
    let tufts: [(x: CGFloat, y: CGFloat)] = [
      (-10, 55.4), (-2, 54.2), (8, 54.4), (18, 55.8), (78, 58.6), (96, 58.4), (112, 58),
    ]
    for (index, tuft) in tufts.enumerated() {
      var blades = Path()
      for blade in 0..<6 {
        let spread = (CGFloat(blade) - 2.5) * 0.9
        let height = 5 + 3 * CGFloat(ViewRhythm.hash(index * 7 + blade, seed: 861))
        let bend =
          CGFloat(sway) * height * 0.22 + spread * 0.8
          + CGFloat(sin(moment.now * 1.3 + Double(index + blade))) * 0.3
        let root = CGPoint(x: tuft.x + spread * 0.4, y: tuft.y)
        blades.move(to: root)
        blades.addQuadCurve(
          to: CGPoint(x: root.x + bend, y: root.y - height),
          control: CGPoint(x: root.x + bend * 0.2, y: root.y - height * 0.6))
      }
      context.stroke(
        blades, with: .color(colour.lit(index % 2 == 0 ? 0 : 0.05).color()), lineWidth: 0.4)
    }
  }

  func headlight(at now: Double) -> ViewHeadlight? { nil }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if moment.look.hour != .night, moment.look.weather != .snow,
      let pass = Self.gulls.pass(at: moment.now)
    {
      let lead = Self.gullPoint(pass, bird: 0, now: moment.now)
      if lead.x > 0, lead.x < 100 {
        return ViewInterest(point: lead, plane: .middle, paw: false, id: pass.index)
      }
    }
    if let walker = Self.walker.interest(at: moment.now) { return walker }
    if let pass = Self.boat.pass(at: moment.now) {
      let point = Self.boatPoint(pass)
      if point.x > 2, point.x < 98 {
        return ViewInterest(
          point: CGPoint(x: point.x, y: point.y - 3), plane: .far, paw: false, id: pass.index)
      }
    }
    return nil
  }
}
