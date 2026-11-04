import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// The sky every view shares, filling the whole scene: its gradient, stars, the moon in its
/// phase, slow clouds, and now and then a plane blinking across.
enum ViewSky {
  /// How much of the window's movement the sky follows.
  static let follow: CGFloat = 0.08
  static let plane = ViewRhythm(seed: 101, slot: 100, chance: 0.6, length: 28...42)

  static func draw(
    _ context: GraphicsContext, size: CGSize, frame: ViewStage.Frame, moment: ViewMoment,
    moon: CGPoint
  ) {
    let palette = moment.palette
    let horizonY = frame.point(CGPoint(x: 0, y: 44)).y
    let windowTop = frame.point(.zero).y
    let height = max(size.height, 1)
    context.fill(
      Path(CGRect(origin: .zero, size: size)),
      with: .linearGradient(
        Gradient(stops: [
          .init(color: palette.skyTop.color(), location: 0),
          .init(
            color: palette.skyTop.mixed(with: palette.skyMiddle, by: 0.5).color(),
            location: max(0.05, min(0.9, windowTop / height * 0.8))),
          .init(
            color: palette.skyMiddle.color(), location: max(0.1, min(0.95, windowTop / height))),
          .init(color: palette.horizon.color(), location: max(0.15, min(0.99, horizonY / height))),
          .init(color: palette.near.color(), location: 1),
        ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    stars(context, size: size, frame: frame, moment: moment)
    drawMoon(context, frame: frame, moment: moment, at: moon)
    clouds(context, frame: frame, moment: moment)
    airplane(context, frame: frame, moment: moment)
  }

  private static func stars(
    _ context: GraphicsContext, size: CGSize, frame: ViewStage.Frame, moment: ViewMoment
  ) {
    let count = Int(90 * moment.palette.stars)
    guard count > 0 else { return }
    let brightness = min(moment.palette.stars, 1)
    let limit = frame.point(CGPoint(x: 0, y: 34)).y
    for index in 0..<count {
      let x = ViewRhythm.hash(index, seed: 1) * Double(size.width + 40) - 20
      let y = ViewRhythm.hash(index, seed: 2) * Double(limit)
      let big = ViewRhythm.hash(index, seed: 3)
      let speed = 0.6 + 2.2 * ViewRhythm.hash(index, seed: 4)
      let twinkle = 0.65 + 0.35 * sin(moment.now * speed + Double(index) * 2.4)
      let r = big > 0.9 ? 1.3 : big > 0.6 ? 0.9 : 0.6
      let fade = min(1, (Double(limit) - y) / 80)
      ViewKit.circle(
        context, CGPoint(x: x + Double(frame.origin.x) * 0.02, y: y), r, ViewColour(0xEEF2F7),
        (0.35 + 0.5 * big) * twinkle * fade * brightness)
    }
  }

  /// The moon's phase from 0 (new) through 0.5 (full) to 1, from a known new moon.
  static func phase(at now: Double) -> Double {
    // 2000-01-06 18:14 UTC, in seconds since 2001-01-01.
    let newMoon = -31_124_760.0
    let month = 29.530_588 * 86_400
    let phase = ((now - newMoon) / month).truncatingRemainder(dividingBy: 1)
    return phase < 0 ? phase + 1 : phase
  }

  private static func drawMoon(
    _ context: GraphicsContext, frame: ViewStage.Frame, moment: ViewMoment, at place: CGPoint
  ) {
    let phase = phase(at: moment.now)
    let light = 1 - abs(phase - 0.5) * 2
    guard light > 0.06 else { return }
    let centre = frame.point(place)
    let radius = frame.unit * 3.4
    let isDark = moment.look.isDark
    let alpha = isDark ? (moment.look.weather == .clear ? 1 : 0.35) : 0.45
    ViewKit.glow(
      context, centre, radius * 4, ViewColour(0xDDE6FF), 0.18 * alpha * (isDark ? 1 : 0.3))
    ViewKit.circle(context, centre, radius, ViewColour(0xF4F1E6), alpha)
    // The shadow side: a disc in the sky's colour slid off the moon as it waxes, back as it wanes.
    let shift = CGFloat((phase < 0.5 ? -1 : 1) * light * 2) * radius
    var shadow = context
    shadow.clip(
      to: Path(
        ellipseIn: CGRect(
          x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius)))
    ViewKit.circle(
      shadow, CGPoint(x: centre.x + shift, y: centre.y), radius * 1.02,
      moment.palette.skyMiddle.mixed(with: moment.palette.skyTop, by: 0.4), alpha * 0.92)
  }

  private static func clouds(
    _ context: GraphicsContext, frame: ViewStage.Frame, moment: ViewMoment
  ) {
    let look = moment.look
    let count = look.weather == .clear ? 5 : 9
    let base: ViewColour =
      switch look.hour {
      case .night: moment.palette.skyMiddle.lit(0.1)
      case .dusk: ViewColour(0xF2A0A8)
      case .day, .morning: ViewColour(0xFFFFFF)
      }
    let alpha = look.weather == .clear ? (look.isDark ? 0.32 : 0.6) : 0.5
    let span: CGFloat = 320
    for index in 0..<count {
      let speed = 0.35 + 0.5 * ViewRhythm.hash(index, seed: 21)
      let start = CGFloat(ViewRhythm.hash(index, seed: 22)) * span
      let x = (start + CGFloat(moment.now * speed)).truncatingRemainder(dividingBy: span) - 110
      let y = -42 + 46 * CGFloat(ViewRhythm.hash(index, seed: 23))
      let width = 22 + 26 * CGFloat(ViewRhythm.hash(index, seed: 24))
      for puff in 0..<4 {
        let px = x + width * (CGFloat(puff) / 3 - 0.5)
        let ph = width * (0.18 + 0.1 * CGFloat(ViewRhythm.hash(index * 7 + puff, seed: 25)))
        let rect = CGRect(
          x: frame.origin.x + (px - width * 0.3) * frame.unit,
          y: frame.origin.y + (y - ph * 0.5) * frame.unit, width: width * 0.6 * frame.unit,
          height: ph * frame.unit)
        context.fill(Path(ellipseIn: rect), with: .color(base.color(alpha * 0.6)))
      }
    }
  }

  /// A plane's lights crossing high up: red and green at the wingtips, a white strobe.
  private static func airplane(
    _ context: GraphicsContext, frame: ViewStage.Frame, moment: ViewMoment
  ) {
    guard let pass = plane.pass(at: moment.now) else { return }
    let point = airplanePoint(pass)
    let centre = frame.point(point)
    let unit = frame.unit
    let isDark = moment.look.isDark
    if !isDark {
      ViewKit.circle(context, centre, unit * 0.4, moment.palette.far.lit(-0.2), 0.7)
      return
    }
    let t = moment.now
    let strobe = (t * 1.1).truncatingRemainder(dividingBy: 1) < 0.08
    let beacon = (t * 0.8 + 0.4).truncatingRemainder(dividingBy: 1) < 0.15
    ViewKit.circle(
      context, CGPoint(x: centre.x - unit * 0.5, y: centre.y), unit * 0.18, ViewColour(0xFF3B3B),
      0.9)
    ViewKit.circle(
      context, CGPoint(x: centre.x + unit * 0.5, y: centre.y), unit * 0.18, ViewColour(0x3DDC84),
      0.9)
    if strobe { ViewKit.glow(context, centre, unit * 1.6, ViewColour(0xFFFFFF), 0.9) }
    if beacon {
      ViewKit.glow(
        context, CGPoint(x: centre.x, y: centre.y + unit * 0.2), unit * 1.1, ViewColour(0xFF3B3B),
        0.7)
    }
  }

  static func airplanePoint(_ pass: ViewRhythm.Pass) -> CGPoint {
    let leftToRight = pass.variant < 0.5
    let x = leftToRight ? -50 + 200 * pass.progress : 150 - 200 * pass.progress
    let y = -36 + 30 * pass.variant + 6 * pass.progress
    return CGPoint(x: x, y: y)
  }

  static func interest(at moment: ViewMoment) -> ViewInterest? {
    guard let pass = plane.pass(at: moment.now) else { return nil }
    let point = airplanePoint(pass)
    // Only while it can be seen through the glass.
    guard point.x > 5, point.x < 95, point.y > -6 else { return nil }
    return ViewInterest(point: point, plane: .far, paw: false, id: pass.index)
  }
}

/// The weather in the air outside, over every plane: rain streaks or falling snow. Fog is laid
/// between the planes by the view itself.
enum ViewAir {
  static func draw(_ context: GraphicsContext, frame: ViewStage.Frame, moment: ViewMoment) {
    switch moment.look.weather {
    case .clear, .fog: break
    case .rain: rain(context, frame: frame, moment: moment)
    case .snow: snow(context, frame: frame, moment: moment)
    }
  }

  private static func rain(_ context: GraphicsContext, frame: ViewStage.Frame, moment: ViewMoment) {
    let colour = moment.palette.skyMiddle.lit(0.55)
    let span: Double = 130
    for index in 0..<110 {
      let near = index % 3 == 0
      let speed = near ? 150.0 : 95
      let x = -10 + 120 * ViewRhythm.hash(index, seed: 61)
      let phase = ViewRhythm.hash(index, seed: 62) * span
      let y = (moment.now * speed + phase).truncatingRemainder(dividingBy: span) - 50
      let length: Double = near ? 5 : 3
      var streak = Path()
      let top = frame.point(CGPoint(x: x + y * 0.12, y: y))
      let bottom = frame.point(CGPoint(x: x + (y + length) * 0.12, y: y + length))
      streak.move(to: top)
      streak.addLine(to: bottom)
      context.stroke(
        streak, with: .color(colour.color(near ? 0.28 : 0.16)),
        lineWidth: frame.unit * (near ? 0.18 : 0.12))
    }
  }

  private static func snow(_ context: GraphicsContext, frame: ViewStage.Frame, moment: ViewMoment) {
    let colour = ViewPalette.snow
    let span: Double = 125
    for index in 0..<120 {
      let depth = index % 3
      let speed = [3.5, 5.5, 8.5][depth]
      let radius = [0.28, 0.42, 0.7][depth]
      let alpha = [0.5, 0.7, 0.9][depth]
      let x = -15 + 130 * ViewRhythm.hash(index, seed: 71)
      let phase = ViewRhythm.hash(index, seed: 72) * span
      let y = (moment.now * speed + phase).truncatingRemainder(dividingBy: span) - 55
      let sway = 2.2 * sin(moment.now * (0.4 + 0.3 * Double(depth)) + Double(index))
      ViewKit.circle(
        context, frame.point(CGPoint(x: x + sway, y: y)), frame.unit * radius, colour, alpha)
    }
  }
}

/// The glass: a faint sheen, the room's lamp reflected in its corner, and the weather on it,
/// drops that cling and then run in rain, frost at the edges in snow.
enum ViewGlass {
  /// A big drop beside the cat now and then, for it to paw at.
  static let bigDrop = ViewRhythm(seed: 77, slot: 16, chance: 0.75, length: 3.5...5.5)

  static func draw(
    _ context: GraphicsContext, frame: ViewStage.Frame, moment: ViewMoment, lampOn: Bool
  ) {
    let unit = frame.unit
    let window = CGRect(
      origin: frame.origin, size: CGSize(width: 100 * unit, height: ViewStage.windowHeight * unit))
    for (start, width, alpha) in [(0.1, 0.12, 0.028), (0.27, 0.05, 0.022)]
      as [(CGFloat, CGFloat, Double)]
    {
      var band = Path()
      band.move(to: CGPoint(x: window.minX + window.width * start, y: window.maxY))
      band.addLine(to: CGPoint(x: window.minX + window.width * (start + width), y: window.maxY))
      band.addLine(
        to: CGPoint(x: window.minX + window.width * (start + width + 0.3), y: window.minY))
      band.addLine(to: CGPoint(x: window.minX + window.width * (start + 0.3), y: window.minY))
      band.closeSubpath()
      context.fill(band, with: .color(.white.opacity(alpha)))
    }
    if lampOn {
      ViewKit.glow(context, frame.point(CGPoint(x: 10, y: 50)), unit * 20, ViewPalette.lamp, 0.13)
    }
    switch moment.look.weather {
    case .rain:
      mist(context, frame: frame, moment: moment)
      rivulets(context, frame: frame, moment: moment)
      drops(context, frame: frame, moment: moment)
    case .snow: frost(context, window: window)
    case .fog: context.fill(Path(window), with: .color(.white.opacity(0.05)))
    case .clear: break
    }
  }

  private static func drops(_ context: GraphicsContext, frame: ViewStage.Frame, moment: ViewMoment)
  {
    let tint = moment.palette.skyMiddle.lit(0.45)
    for index in 0..<46 {
      let rhythm = ViewRhythm(
        seed: UInt64(index) &* 131 &+ 9, slot: 11, chance: 0.85, length: 6...10.5)
      guard let pass = rhythm.pass(at: moment.now) else { continue }
      let x = 2 + 96 * ViewRhythm.hash(Int(pass.index) &* 64 &+ index, seed: 81)
      let y0 = 2 + 50 * ViewRhythm.hash(Int(pass.index) &* 64 &+ index, seed: 82)
      let size = 0.35 + 0.5 * pass.variant
      drop(context, frame: frame, x: x, y0: y0, size: size, progress: pass.progress, tint: tint)
    }
    if let pass = bigDrop.pass(at: moment.now) {
      let point = bigDropPlace(pass)
      drop(
        context, frame: frame, x: point.x, y0: point.y, size: 1.1, progress: pass.progress,
        tint: tint)
    }
  }

  /// A fine mist of tiny beads all over the glass, a different scatter every half minute.
  private static func mist(_ context: GraphicsContext, frame: ViewStage.Frame, moment: ViewMoment) {
    let tint = moment.palette.skyMiddle.lit(0.5)
    let scatter = Int((moment.now / 30).rounded(.down)) % 10_000
    for index in 0..<90 {
      let id = scatter * 128 + index
      let point = frame.point(
        CGPoint(
          x: 1 + 98 * ViewRhythm.hash(id, seed: 84),
          y: 1 + (ViewStage.windowHeight - 2) * ViewRhythm.hash(id, seed: 85)))
      ViewKit.circle(
        context, point, frame.unit * (0.08 + 0.1 * ViewRhythm.hash(id, seed: 86)), tint, 0.3)
    }
  }

  /// Rivulets: water finding its way down the glass in wavering lines, each running for a while
  /// and then drying off as another starts somewhere else.
  private static func rivulets(
    _ context: GraphicsContext, frame: ViewStage.Frame, moment: ViewMoment
  ) {
    let tint = moment.palette.skyMiddle.lit(0.5)
    for index in 0..<7 {
      let rhythm = ViewRhythm(
        seed: UInt64(index) &* 977 &+ 41, slot: 24, chance: 0.8, length: 14...22)
      guard let pass = rhythm.pass(at: moment.now) else { continue }
      let x0 = 4 + 92 * ViewRhythm.hash(Int(pass.index) &* 16 &+ index, seed: 87)
      let reach =
        min(pass.progress / 0.4, 1) * ViewStage.windowHeight * (0.4 + 0.6 * pass.variant)
      let fade = pass.progress > 0.75 ? (1 - pass.progress) / 0.25 : 1
      var line = Path()
      line.move(to: frame.point(CGPoint(x: x0, y: 0)))
      var y = 0.0
      while y < reach {
        y += 1.2
        let wander =
          1.1 * sin(y * 0.18 + Double(index) * 2) + 0.25 * sin(y * 0.9 + pass.variant * 6)
        line.addLine(to: frame.point(CGPoint(x: x0 + wander, y: y)))
      }
      context.stroke(
        line, with: .color(tint.color(0.16 * fade)),
        style: StrokeStyle(lineWidth: frame.unit * 0.22, lineCap: .round, lineJoin: .round))
      context.stroke(
        line, with: .color(ViewColour(0xFFFFFF).color(0.12 * fade)),
        style: StrokeStyle(lineWidth: frame.unit * 0.07, lineCap: .round, lineJoin: .round))
    }
  }

  /// One drop: it gathers for most of its pass, then runs down the glass leaving a thin trail.
  private static func drop(
    _ context: GraphicsContext, frame: ViewStage.Frame, x: Double, y0: Double, size: Double,
    progress: Double, tint: ViewColour
  ) {
    let gather = min(progress / 0.7, 1)
    let run = max(0, (progress - 0.7) / 0.3)
    let y = y0 + run * run * 40
    let radius = size * (0.5 + 0.5 * gather)
    if run > 0 {
      var trail = Path()
      trail.move(to: frame.point(CGPoint(x: x, y: y0)))
      trail.addLine(to: frame.point(CGPoint(x: x + 0.3 * run, y: y)))
      context.stroke(trail, with: .color(tint.color(0.18)), lineWidth: frame.unit * radius * 0.5)
    }
    let centre = frame.point(CGPoint(x: x + 0.3 * run, y: y))
    let fade = progress > 0.95 ? (1 - progress) / 0.05 : 1
    ViewKit.circle(context, centre, frame.unit * radius, tint, 0.32 * fade)
    ViewKit.circle(
      context,
      CGPoint(x: centre.x - frame.unit * radius * 0.3, y: centre.y - frame.unit * radius * 0.35),
      frame.unit * radius * 0.28, ViewColour(0xFFFFFF), 0.55 * fade)
  }

  private static func frost(_ context: GraphicsContext, window: CGRect) {
    for corner in [
      CGPoint(x: window.minX, y: window.maxY), CGPoint(x: window.maxX, y: window.maxY),
    ] {
      context.fill(
        Path(
          ellipseIn: CGRect(
            x: corner.x - window.width * 0.3, y: corner.y - window.height * 0.4,
            width: window.width * 0.6, height: window.height * 0.8)),
        with: .radialGradient(
          Gradient(colors: [.white.opacity(0.22), .white.opacity(0)]), center: corner,
          startRadius: 0, endRadius: window.width * 0.3))
    }
  }

  static func bigDropPlace(_ pass: ViewRhythm.Pass) -> CGPoint {
    CGPoint(x: 70 + 22 * pass.variant, y: 26 + 14 * ViewRhythm.hash(Int(pass.index), seed: 83))
  }

  static func interest(at moment: ViewMoment) -> ViewInterest? {
    guard moment.look.weather == .rain, let pass = bigDrop.pass(at: moment.now) else { return nil }
    let place = bigDropPlace(pass)
    let run = max(0, (pass.progress - 0.7) / 0.3)
    return ViewInterest(
      point: CGPoint(x: place.x, y: place.y + run * run * 40), plane: nil, paw: true,
      id: pass.index)
  }
}
