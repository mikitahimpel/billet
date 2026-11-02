import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// A window of a building in a view, lit or dark by the view's life rather than baked into its
/// plane, so it can go dark or light up.
struct ViewLitWindow: Hashable, Sendable {
  var id: Int
  var rect: CGRect
  var plane: ViewPlane
  /// A window with a TV on behind it flickers blue rather than glowing amber.
  var isTV = false
}

/// Flat shapes the views are built from, drawn in stage units. Silhouettes in one colour with a
/// lighter lit side, no outlines, thin lines only for wires and rails (see the style bible).
enum ViewKit {
  static func rect(
    _ context: GraphicsContext, _ rect: CGRect, _ colour: ViewColour, _ alpha: Double = 1
  ) {
    context.fill(Path(rect), with: .color(colour.color(alpha)))
  }

  static func circle(
    _ context: GraphicsContext, _ centre: CGPoint, _ radius: CGFloat, _ colour: ViewColour,
    _ alpha: Double = 1
  ) {
    context.fill(
      Path(
        ellipseIn: CGRect(
          x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius)),
      with: .color(colour.color(alpha)))
  }

  /// A soft round glow that fades out to nothing at `radius`.
  static func glow(
    _ context: GraphicsContext, _ centre: CGPoint, _ radius: CGFloat, _ colour: ViewColour,
    _ alpha: Double
  ) {
    guard alpha > 0.001, radius > 0 else { return }
    context.fill(
      Path(
        ellipseIn: CGRect(
          x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius)),
      with: .radialGradient(
        Gradient(stops: [
          .init(color: colour.color(alpha), location: 0),
          .init(color: colour.color(alpha * 0.35), location: 0.35),
          .init(color: colour.color(0), location: 1),
        ]), center: centre, startRadius: 0, endRadius: radius))
  }

  /// A gable house: walls from `base` up `wall`, a roof `roof` higher, and a lighter lit side on
  /// the right slope. Snow caps the roof when it snows.
  static func house(
    _ context: GraphicsContext, x: CGFloat, base: CGFloat, width: CGFloat, wall: CGFloat,
    roof: CGFloat, colour: ViewColour, look: ViewLook, overhang: CGFloat = 1.2
  ) {
    let eave = base - wall
    rect(context, CGRect(x: x, y: eave, width: width, height: wall), colour)
    var gable = Path()
    gable.move(to: CGPoint(x: x - overhang, y: eave + 0.4))
    gable.addLine(to: CGPoint(x: x + width / 2, y: eave - roof))
    gable.addLine(to: CGPoint(x: x + width + overhang, y: eave + 0.4))
    gable.closeSubpath()
    context.fill(gable, with: .color(colour.lit(-0.12).color()))
    var lit = Path()
    lit.move(to: CGPoint(x: x + width / 2, y: eave - roof))
    lit.addLine(to: CGPoint(x: x + width + overhang, y: eave + 0.4))
    lit.addLine(to: CGPoint(x: x + width / 2 + 1, y: eave + 0.4))
    lit.closeSubpath()
    context.fill(lit, with: .color(colour.lit(look.isDark ? 0.06 : 0.12).color()))
    if look.weather == .snow {
      var cap = Path()
      cap.move(to: CGPoint(x: x - overhang, y: eave + 0.4))
      cap.addLine(to: CGPoint(x: x + width / 2, y: eave - roof))
      cap.addLine(to: CGPoint(x: x + width + overhang, y: eave + 0.4))
      cap.addLine(to: CGPoint(x: x + width + overhang - 0.6, y: eave + 1.3))
      cap.addLine(to: CGPoint(x: x + width / 2, y: eave - roof + 1.4))
      cap.addLine(to: CGPoint(x: x - overhang + 0.6, y: eave + 1.3))
      cap.closeSubpath()
      context.fill(cap, with: .color(snow(look).color()))
    }
  }

  /// The snow on roofs and lawns: blue-white at night, white by day.
  static func snow(_ look: ViewLook) -> ViewColour {
    ViewPalette.snow.mixed(with: look.palette.skyMiddle, by: look.isDark ? 0.55 : 0.15)
  }

  /// The dark frame a window sits in. The glass itself is drawn by the life, lit or not.
  static func windowFrame(_ context: GraphicsContext, _ window: CGRect, _ colour: ViewColour) {
    rect(context, window.insetBy(dx: -0.35, dy: -0.35), colour.lit(-0.25))
    rect(context, window, colour.lit(-0.35))
  }

  /// A round tree of overlapping circles on a short trunk.
  static func tree(
    _ context: GraphicsContext, x: CGFloat, base: CGFloat, size: CGFloat, colour: ViewColour,
    seed: Int, look: ViewLook
  ) {
    rect(
      context,
      CGRect(x: x - size * 0.06, y: base - size * 0.7, width: size * 0.12, height: size * 0.7),
      colour.lit(-0.15))
    let puffs = 5
    for index in 0..<puffs {
      let a = ViewRhythm.hash(seed * 31 + index, seed: 11)
      let b = ViewRhythm.hash(seed * 31 + index, seed: 12)
      let centre = CGPoint(
        x: x + (CGFloat(a) - 0.5) * size * 0.9, y: base - size * (0.75 + CGFloat(b) * 0.45))
      circle(context, centre, size * (0.32 + CGFloat(b) * 0.12), colour)
    }
    circle(
      context, CGPoint(x: x + size * 0.15, y: base - size * 1.05), size * 0.22,
      colour.lit(look.isDark ? 0.05 : 0.1))
    if look.weather == .snow {
      // Snow lies on the tops of the puffs as flat caps.
      for index in 0..<3 {
        let cx = x + size * (CGFloat(index) - 1) * 0.28
        let top = base - size * (1.28 - 0.08 * abs(CGFloat(index) - 1))
        context.fill(
          Path(
            ellipseIn: CGRect(x: cx - size * 0.2, y: top, width: size * 0.4, height: size * 0.1)),
          with: .color(snow(look).color(0.75)))
      }
    }
  }

  /// A pointed evergreen, three tiers.
  static func pine(
    _ context: GraphicsContext, x: CGFloat, base: CGFloat, height: CGFloat, colour: ViewColour,
    look: ViewLook
  ) {
    for tier in 0..<3 {
      let t = CGFloat(tier)
      let bottom = base - height * (0.12 + t * 0.26)
      let width = height * (0.5 - t * 0.12)
      var path = Path()
      path.move(to: CGPoint(x: x - width / 2, y: bottom))
      path.addLine(to: CGPoint(x: x, y: bottom - height * 0.42))
      path.addLine(to: CGPoint(x: x + width / 2, y: bottom))
      path.closeSubpath()
      context.fill(path, with: .color(colour.color()))
      if look.weather == .snow {
        var cap = Path()
        cap.move(to: CGPoint(x: x - width * 0.22, y: bottom - height * 0.25))
        cap.addLine(to: CGPoint(x: x, y: bottom - height * 0.42))
        cap.addLine(to: CGPoint(x: x + width * 0.22, y: bottom - height * 0.25))
        cap.closeSubpath()
        context.fill(cap, with: .color(snow(look).color(0.85)))
      }
    }
    rect(
      context, CGRect(x: x - 0.4, y: base - height * 0.14, width: 0.8, height: height * 0.14),
      colour)
  }

  /// A wooden power pole with a cross-arm, returning where its wires hang from.
  @discardableResult
  static func pole(
    _ context: GraphicsContext, x: CGFloat, top: CGFloat, base: CGFloat, colour: ViewColour
  ) -> [CGPoint] {
    rect(context, CGRect(x: x - 0.45, y: top, width: 0.9, height: base - top), colour)
    rect(context, CGRect(x: x - 4, y: top + 1.2, width: 8, height: 0.7), colour)
    rect(context, CGRect(x: x - 2.6, y: top + 4, width: 5.2, height: 0.5), colour)
    for dx in [-3.4, 3.4] as [CGFloat] {
      rect(context, CGRect(x: x + dx - 0.3, y: top + 0.5, width: 0.6, height: 0.8), colour)
    }
    rect(context, CGRect(x: x + 0.45, y: top + 6, width: 1.6, height: 2.4), colour)
    return [
      CGPoint(x: x - 3.4, y: top + 0.6), CGPoint(x: x, y: top + 0.6),
      CGPoint(x: x + 3.4, y: top + 0.6), CGPoint(x: x - 2.4, y: top + 4.2),
      CGPoint(x: x + 2.4, y: top + 4.2),
    ]
  }

  /// A wire hanging between two points, sagging by `sag` in the middle.
  static func wire(
    _ context: GraphicsContext, from: CGPoint, to: CGPoint, sag: CGFloat, colour: ViewColour,
    width: CGFloat = 0.22
  ) {
    var path = Path()
    path.move(to: from)
    path.addQuadCurve(
      to: to, control: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 + 2 * sag))
    context.stroke(path, with: .color(colour.color()), lineWidth: width)
  }

  /// A point on a wire, `share` of the way along, for things that sit on it.
  static func onWire(from: CGPoint, to: CGPoint, sag: CGFloat, share: CGFloat) -> CGPoint {
    let control = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 + 2 * sag)
    let u = 1 - share
    return CGPoint(
      x: u * u * from.x + 2 * u * share * control.x + share * share * to.x,
      y: u * u * from.y + 2 * u * share * control.y + share * share * to.y)
  }

  /// The town's water tower: a round tank with a cone lid on four splayed legs and a catwalk.
  static func waterTower(
    _ context: GraphicsContext, x: CGFloat, top: CGFloat, base: CGFloat, size: CGFloat,
    colour: ViewColour, look: ViewLook
  ) {
    let tankTop = top + size * 0.32
    let tankBottom = tankTop + size * 0.62
    let half = size * 0.5
    for (foot, head) in [(-0.62, -0.36), (-0.2, -0.14), (0.2, 0.14), (0.62, 0.36)]
      as [(CGFloat, CGFloat)]
    {
      var leg = Path()
      leg.move(to: CGPoint(x: x + head * size, y: tankBottom))
      leg.addLine(to: CGPoint(x: x + foot * size, y: base))
      context.stroke(leg, with: .color(colour.color()), lineWidth: size * 0.05)
    }
    for share in [0.35, 0.68] as [CGFloat] {
      let y = tankBottom + (base - tankBottom) * share
      let spread = 0.36 + 0.26 * share
      var brace = Path()
      brace.move(to: CGPoint(x: x - spread * size, y: y))
      brace.addLine(to: CGPoint(x: x + spread * size, y: y))
      context.stroke(brace, with: .color(colour.color()), lineWidth: size * 0.025)
    }
    context.fill(
      Path(
        roundedRect: CGRect(x: x - half, y: tankTop, width: size, height: tankBottom - tankTop),
        cornerRadius: size * 0.14),
      with: .color(colour.color()))
    rect(
      context,
      CGRect(
        x: x + half * 0.2, y: tankTop + size * 0.04, width: half * 0.7,
        height: tankBottom - tankTop - size * 0.08), colour.lit(look.isDark ? 0.06 : 0.12))
    rect(
      context,
      CGRect(
        x: x - half - size * 0.08, y: tankBottom - size * 0.04, width: size * 1.16,
        height: size * 0.05), colour.lit(-0.1))
    var lid = Path()
    lid.move(to: CGPoint(x: x - half - size * 0.04, y: tankTop + size * 0.02))
    lid.addLine(to: CGPoint(x: x, y: top))
    lid.addLine(to: CGPoint(x: x + half + size * 0.04, y: tankTop + size * 0.02))
    lid.closeSubpath()
    context.fill(lid, with: .color(colour.lit(-0.08).color()))
    if look.weather == .snow {
      var cap = Path()
      cap.move(to: CGPoint(x: x - half * 0.8, y: tankTop - size * 0.02))
      cap.addLine(to: CGPoint(x: x, y: top))
      cap.addLine(to: CGPoint(x: x + half * 0.8, y: tankTop - size * 0.02))
      cap.closeSubpath()
      context.fill(cap, with: .color(snow(look).color(0.85)))
    }
  }

  /// A street lamp's post and arm. Its head and light are drawn by the life, so it can stutter.
  static func streetLampPost(
    _ context: GraphicsContext, x: CGFloat, top: CGFloat, base: CGFloat, colour: ViewColour
  ) {
    rect(context, CGRect(x: x - 0.5, y: top, width: 1, height: base - top), colour)
    rect(context, CGRect(x: x - 0.9, y: base - 2, width: 1.8, height: 2), colour)
    var arm = Path()
    arm.move(to: CGPoint(x: x, y: top + 1.6))
    arm.addQuadCurve(to: CGPoint(x: x - 5, y: top + 0.3), control: CGPoint(x: x - 1, y: top - 0.6))
    context.stroke(arm, with: .color(colour.color()), lineWidth: 0.6)
  }

  /// A parked car seen side on, nose to the right unless `facingLeft`.
  static func car(
    _ context: GraphicsContext, x: CGFloat, base: CGFloat, length: CGFloat, body: ViewColour,
    facingLeft: Bool = false
  ) {
    let height = length * 0.3
    context.fill(
      Path(
        roundedRect: CGRect(x: x, y: base - height * 0.62, width: length, height: height * 0.45),
        cornerRadius: height * 0.12),
      with: .color(body.color()))
    var cabin = Path()
    let rear = facingLeft ? x + length * 0.78 : x + length * 0.22
    let front = facingLeft ? x + length * 0.3 : x + length * 0.7
    cabin.move(to: CGPoint(x: min(rear, front) - length * 0.04, y: base - height * 0.6))
    cabin.addLine(to: CGPoint(x: min(rear, front) + length * 0.08, y: base - height))
    cabin.addLine(to: CGPoint(x: max(rear, front) - length * 0.1, y: base - height))
    cabin.addLine(to: CGPoint(x: max(rear, front) + length * 0.06, y: base - height * 0.6))
    cabin.closeSubpath()
    context.fill(cabin, with: .color(body.lit(-0.1).color()))
    for share in [0.2, 0.8] as [CGFloat] {
      circle(
        context, CGPoint(x: x + length * share, y: base - height * 0.16), height * 0.17,
        body.lit(-0.5))
    }
  }

  /// A picket fence along `base`, from `from` to `to`.
  static func fence(
    _ context: GraphicsContext, from: CGFloat, to: CGFloat, base: CGFloat, height: CGFloat,
    colour: ViewColour, look: ViewLook
  ) {
    rect(
      context, CGRect(x: from, y: base - height * 0.7, width: to - from, height: height * 0.12),
      colour)
    rect(
      context, CGRect(x: from, y: base - height * 0.3, width: to - from, height: height * 0.12),
      colour)
    var x = from
    while x < to {
      var picket = Path()
      picket.move(to: CGPoint(x: x, y: base))
      picket.addLine(to: CGPoint(x: x, y: base - height * 0.88))
      picket.addLine(to: CGPoint(x: x + 0.6, y: base - height))
      picket.addLine(to: CGPoint(x: x + 1.2, y: base - height * 0.88))
      picket.addLine(to: CGPoint(x: x + 1.2, y: base))
      picket.closeSubpath()
      context.fill(picket, with: .color(colour.color()))
      if look.weather == .snow {
        rect(
          context, CGRect(x: x, y: base - height * 0.9, width: 1.2, height: 0.5), snow(look), 0.85)
      }
      x += 2.1
    }
  }

  /// A long low hill line across the plate: from `base`, each wave rises its own height.
  static func hills(
    _ context: GraphicsContext, base: CGFloat, waves: [CGFloat], colour: ViewColour
  ) {
    let plate = ViewStage.plate
    var path = Path()
    path.move(to: CGPoint(x: plate.minX, y: plate.maxY))
    path.addLine(to: CGPoint(x: plate.minX, y: base))
    let step = plate.width / CGFloat(max(waves.count, 1))
    for (index, wave) in waves.enumerated() {
      let start = plate.minX + CGFloat(index) * step
      path.addQuadCurve(
        to: CGPoint(x: start + step, y: base),
        control: CGPoint(x: start + step / 2, y: base - 2 * wave))
    }
    path.addLine(to: CGPoint(x: plate.maxX, y: plate.maxY))
    path.closeSubpath()
    context.fill(path, with: .color(colour.color()))
  }

  /// Ground from `top` down past the plate's bottom.
  static func ground(_ context: GraphicsContext, top: CGFloat, colour: ViewColour) {
    let plate = ViewStage.plate
    rect(
      context, CGRect(x: plate.minX, y: top, width: plate.width, height: plate.maxY - top), colour)
  }

  /// A lit window's glow at `level` from 0 to 1, amber or TV blue.
  static func litWindow(
    _ context: GraphicsContext, _ window: ViewLitWindow, level: Double, flicker: Double = 1
  ) {
    guard level > 0.01 else { return }
    let colour =
      window.isTV
      ? ViewPalette.tv.mixed(with: ViewColour(0xFFFFFF), by: 0.2 * flicker) : ViewPalette.lamp
    let rect = window.rect
    context.fill(
      Path(rect),
      with: .linearGradient(
        Gradient(colors: [
          (window.isTV ? colour : ViewPalette.lampCore).color(
            level * (window.isTV ? 0.55 + 0.35 * flicker : 0.95)),
          colour.color(level * 0.85),
        ]), startPoint: CGPoint(x: rect.midX, y: rect.minY),
        endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
    glow(
      context, CGPoint(x: rect.midX, y: rect.midY), max(rect.width, rect.height) * 1.3, colour,
      0.22 * level)
  }
}
