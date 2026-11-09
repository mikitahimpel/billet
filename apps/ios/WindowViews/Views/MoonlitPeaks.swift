import CoreGraphics
import Foundation
import Pet
import SwiftUI

struct MoonlitPeaks: ViewRecipe {
  static let streetBase: CGFloat = 46
  static let middleBase: CGFloat = 40
  static let shootingStar = ViewShootingStar(
    rhythm: ViewRhythm(seed: 1101, slot: 24, chance: 0.5, length: 0.9...1.4),
    area: CGRect(x: 8, y: -6, width: 84, height: 6))
  static let gondola = ViewRhythm(seed: 1111, slot: 50, chance: 0.75, length: 30...40)
  static let fox = ViewRhythm(seed: 1121, slot: 75, chance: 0.5, length: 16...22)
  static let pylons: [CGFloat] = [18, 76]
  static let chimney = CGPoint(x: 77, y: 26.6)

  var moon: CGPoint { CGPoint(x: 74, y: -14) }
  var livePlanes: Set<ViewPlane> { [.far, .middle, .street] }

  static func grade(_ palette: inout ViewPalette, hour: ViewHour, share: Double) {
    let colours: [UInt32]
    switch hour {
    case .night: colours = [0x060A1E, 0x1A2A55, 0x4A6496, 0x5A6E98, 0x26345A, 0x1A2440, 0x10162A]
    case .dusk: colours = [0x2A2A5E, 0x7A6AA8, 0xF0A090, 0x8A7AA0, 0x4A4070, 0x342C52, 0x201A36]
    case .day: colours = [0x4A8ED8, 0x9CCBEE, 0xE8F2FA, 0xB8C8DC, 0x7E92AE, 0x5E7290, 0x3E4E66]
    case .morning:
      colours = [0x6A86C8, 0xC8C0E0, 0xFFD8C0, 0xC0B8D0, 0x8A88A8, 0x686888, 0x464660]
    }
    palette.grade(colours, share: share)
    palette.stars *= 1.6
    if hour == .night || hour == .dusk { palette.litShare = max(palette.litShare, 0.9) }
  }

  func paint(_ plane: ViewPlane, _ context: GraphicsContext, look: ViewLook) {
    let colour = look.palette.colour(plane)
    switch plane {
    case .far: paintFar(context, colour: colour, look: look)
    case .middle: paintMiddle(context, colour: colour, look: look)
    case .street: paintStreet(context, colour: colour, look: look)
    case .near: paintNear(context, colour: colour, look: look)
    }
  }

  /// Snow that lies here whatever the weather.
  private static func snowLook(_ look: ViewLook) -> ViewLook {
    ViewLook(view: look.view, hour: look.hour, weather: .snow)
  }

  // MARK: - Far: the peaks

  static let peaks: [(apex: CGPoint, left: CGFloat, right: CGFloat)] = [
    (CGPoint(x: -22, y: 14), -64, 16), (CGPoint(x: 22, y: 8), -14, 60),
    (CGPoint(x: 58, y: 16), 30, 90), (CGPoint(x: 96, y: 10), 66, 136),
    (CGPoint(x: 132, y: 15), 104, 172),
  ]

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let palette = look.palette
    ViewKit.hills(
      context, base: 30, waves: [6, 9, 5, 10, 7, 8, 6],
      colour: colour.mixed(
        with: palette.horizon, by: 0.45))
    let snow = ViewKit.snow(look).mixed(with: colour, by: 0.2)
    let shade = snow.mixed(with: palette.skyTop, by: look.isDark ? 0.35 : 0.2)
    let lit = snow.lit(look.isDark ? 0.08 : 0.15)
    let rock = colour.lit(-0.18)
    let base: CGFloat = 36
    for (index, peak) in Self.peaks.enumerated() {
      let apex = peak.apex
      let leftFoot = CGPoint(x: peak.left, y: base)
      let rightFoot = CGPoint(x: peak.right, y: base)
      let shoulder = CGFloat(ViewRhythm.hash(index, seed: 1131))
      var mountain = Path()
      mountain.move(to: leftFoot)
      mountain.addLine(to: Self.along(leftFoot, apex, 0.55 + 0.1 * shoulder, bump: -1.2))
      mountain.addLine(to: apex)
      mountain.addLine(to: Self.along(apex, rightFoot, 0.35, bump: -1.4 * shoulder))
      mountain.addLine(to: rightFoot)
      mountain.closeSubpath()
      context.fill(mountain, with: .color(rock.color()))
      var cap = context
      cap.clip(to: mountain)
      let depth = (base - apex.y) * 0.68
      let snowLine = apex.y + depth
      var field = Path()
      field.move(to: CGPoint(x: peak.left - 2, y: apex.y - 2))
      field.addLine(to: CGPoint(x: peak.right + 2, y: apex.y - 2))
      field.addLine(to: CGPoint(x: peak.right + 2, y: snowLine - 2))
      let teeth = 7
      for tooth in (0...teeth).reversed() {
        let x = peak.left + (peak.right - peak.left) * CGFloat(tooth) / CGFloat(teeth)
        let drop = CGFloat(ViewRhythm.hash(index * 13 + tooth, seed: 1132)) * 4
        field.addLine(to: CGPoint(x: x, y: snowLine - 2 + (tooth % 2 == 0 ? drop : -1)))
      }
      field.closeSubpath()
      cap.fill(field, with: .color(shade.color()))
      var face = Path()
      face.move(to: apex)
      face.addLine(to: CGPoint(x: peak.right + 2, y: base))
      face.addLine(to: CGPoint(x: apex.x + 2, y: base))
      face.closeSubpath()
      var litCap = cap
      litCap.clip(to: field)
      litCap.fill(face, with: .color(lit.color()))
      for rib in 0..<3 {
        let spread = (CGFloat(rib) - 1) * 3.4
        var ridge = Path()
        ridge.move(to: CGPoint(x: apex.x + spread * 0.2, y: apex.y + 1))
        ridge.addQuadCurve(
          to: CGPoint(x: apex.x + spread * 2.2, y: snowLine + 1),
          control: CGPoint(x: apex.x + spread, y: apex.y + depth * 0.5))
        cap.stroke(ridge, with: .color(rock.color(0.55)), lineWidth: 0.3)
      }
    }
    ViewKit.ground(context, top: base - 0.5, colour: shade.mixed(with: colour, by: 0.3))
  }

  /// A point `share` of the way from `a` to `b`, pushed `bump` up or down.
  private static func along(_ a: CGPoint, _ b: CGPoint, _ share: CGFloat, bump: CGFloat) -> CGPoint
  {
    CGPoint(x: a.x + (b.x - a.x) * share, y: a.y + (b.y - a.y) * share + bump)
  }

  // MARK: - Middle: the pine valley and the gondola

  /// The cable's height at `x`, rising from the valley on the right up to the left.
  static func cableY(_ x: CGFloat) -> CGFloat {
    30 - (x + 45) * 32 / 190
  }

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let snowy = Self.snowLook(look)
    let snow = ViewKit.snow(look).mixed(with: colour, by: 0.45)
    ViewKit.hills(
      context, base: Self.middleBase - 1, waves: [2, 3.4, 1.6, 2.8, 2, 3.2, 1.8, 2.6],
      colour: snow)
    ViewKit.ground(context, top: Self.middleBase, colour: snow.lit(-0.04))
    // The pylons, behind the trees.
    let steel = colour.lit(-0.2)
    for x in Self.pylons {
      let top = Self.cableY(x) + 1.4
      for side in [-1, 1] as [CGFloat] {
        var leg = Path()
        leg.move(to: CGPoint(x: x + side * 2.2, y: Self.middleBase))
        leg.addLine(to: CGPoint(x: x + side * 0.5, y: top))
        context.stroke(leg, with: .color(steel.color()), lineWidth: 0.4)
      }
      var share: CGFloat = 0.15
      while share < 1 {
        let y = top + (Self.middleBase - top) * share
        let half = 0.5 + 1.7 * share
        var brace = Path()
        brace.move(to: CGPoint(x: x - half, y: y))
        brace.addLine(to: CGPoint(x: x + half, y: y + 2))
        brace.move(to: CGPoint(x: x + half, y: y))
        brace.addLine(to: CGPoint(x: x - half, y: y + 2))
        context.stroke(brace, with: .color(steel.color(0.8)), lineWidth: 0.15)
        share += 0.22
      }
      ViewKit.rect(context, CGRect(x: x - 2.4, y: top - 0.6, width: 4.8, height: 0.6), steel)
    }
    for row in 0..<2 {
      for index in 0..<26 {
        let id = row * 40 + index
        let x = -44 + CGFloat(index) * 7.4 + CGFloat(ViewRhythm.hash(id, seed: 1141)) * 4
        let height = (row == 0 ? 7 : 10) + 4 * CGFloat(ViewRhythm.hash(id, seed: 1142))
        ViewKit.pine(
          context, x: x, base: Self.middleBase - 1.5 + CGFloat(row) * 2.4, height: height,
          colour: colour.lit(row == 0 ? 0.03 : -0.04), look: snowy)
      }
    }
    for offset in [0, 0.5] as [CGFloat] {
      var cable = Path()
      cable.move(to: CGPoint(x: -45, y: Self.cableY(-45) + offset))
      cable.addLine(to: CGPoint(x: 145, y: Self.cableY(145) + offset))
      context.stroke(cable, with: .color(steel.lit(-0.1).color()), lineWidth: 0.16)
    }
  }

  // MARK: - Street: the chalet

  static let chalet = CGRect(x: 56, y: 35, width: 26, height: 11)

  static let chaletWindows: [ViewLitWindow] = [
    ViewLitWindow(id: 1150, rect: CGRect(x: 60, y: 36.4, width: 3.6, height: 2.6), plane: .street),
    ViewLitWindow(
      id: 1151, rect: CGRect(x: 74.4, y: 36.4, width: 3.6, height: 2.6), plane: .street),
    ViewLitWindow(id: 1152, rect: CGRect(x: 59, y: 41.6, width: 4, height: 3), plane: .street),
    ViewLitWindow(id: 1153, rect: CGRect(x: 75, y: 41.6, width: 4, height: 3), plane: .street),
    ViewLitWindow(id: 1154, rect: CGRect(x: 68, y: 30.2, width: 2, height: 2.4), plane: .street),
  ]

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let base = Self.streetBase
    let snowy = Self.snowLook(look)
    let snow = ViewKit.snow(look).mixed(with: colour, by: 0.35)
    let pines: [CGFloat] = [4, 14, 26, 40, 92, 104, 118]
    for (index, x) in pines.enumerated() {
      ViewKit.pine(
        context, x: x, base: base + 0.4,
        height: 13 + 6 * CGFloat(ViewRhythm.hash(index, seed: 1151)),
        colour: colour.lit(index % 2 == 0 ? 0 : -0.04), look: snowy)
    }
    let wood = colour.mixed(with: ViewColour(0x7A5034), by: look.isDark ? 0.3 : 0.5)
    let wall = Self.chalet
    ViewKit.rect(context, wall, wood)
    var plank = wall.minY + 1
    while plank < wall.maxY {
      ViewKit.rect(
        context, CGRect(x: wall.minX, y: plank, width: wall.width, height: 0.12), wood.lit(-0.15))
      plank += 1.1
    }
    for window in Self.chaletWindows { ViewKit.windowFrame(context, window.rect, wood) }
    ViewKit.rect(
      context, CGRect(x: 66.6, y: 41, width: 4, height: 5), wood.lit(-0.25))
    ViewKit.rect(
      context, CGRect(x: wall.minX - 1, y: 39.6, width: wall.width + 2, height: 0.6), wood.lit(0.06)
    )
    var post = wall.minX - 0.6
    while post < wall.maxX + 1 {
      ViewKit.rect(context, CGRect(x: post, y: 39.8, width: 0.3, height: 1.4), wood.lit(0.04))
      post += 1.3
    }
    ViewKit.rect(
      context, CGRect(x: wall.minX - 1, y: 41, width: wall.width + 2, height: 0.4), wood.lit(-0.1))
    ViewKit.rect(
      context, CGRect(x: wall.minX - 1, y: 39.2, width: wall.width + 2, height: 0.45), snow)
    ViewKit.rect(
      context, CGRect(x: Self.chimney.x - 1, y: Self.chimney.y, width: 2.2, height: 6),
      colour.mixed(with: ViewColour(0x8A7A70), by: 0.3))
    let apex = CGPoint(x: wall.midX, y: 24.6)
    var roof = Path()
    roof.move(to: CGPoint(x: wall.minX - 3, y: wall.minY + 1))
    roof.addLine(to: apex)
    roof.addLine(to: CGPoint(x: wall.maxX + 3, y: wall.minY + 1))
    roof.closeSubpath()
    context.fill(roof, with: .color(wood.lit(-0.2).color()))
    var gable = Path()
    gable.move(to: CGPoint(x: wall.minX + 0.5, y: wall.minY + 0.4))
    gable.addLine(to: CGPoint(x: apex.x, y: apex.y + 2.4))
    gable.addLine(to: CGPoint(x: wall.maxX - 0.5, y: wall.minY + 0.4))
    gable.closeSubpath()
    context.fill(gable, with: .color(wood.lit(0.04).color()))
    ViewKit.windowFrame(context, Self.chaletWindows[4].rect, wood)
    var quilt = Path()
    quilt.move(to: CGPoint(x: wall.minX - 3.6, y: wall.minY + 1.4))
    quilt.addLine(to: CGPoint(x: apex.x, y: apex.y - 1.4))
    quilt.addLine(to: CGPoint(x: wall.maxX + 3.6, y: wall.minY + 1.4))
    quilt.addQuadCurve(
      to: CGPoint(x: wall.maxX + 2.4, y: wall.minY + 0.4),
      control: CGPoint(x: wall.maxX + 3.8, y: wall.minY + 0.4))
    quilt.addLine(to: CGPoint(x: apex.x, y: apex.y + 0.6))
    quilt.addLine(to: CGPoint(x: wall.minX - 2.4, y: wall.minY + 0.4))
    quilt.addQuadCurve(
      to: CGPoint(x: wall.minX - 3.6, y: wall.minY + 1.4),
      control: CGPoint(x: wall.minX - 3.8, y: wall.minY + 0.4))
    quilt.closeSubpath()
    context.fill(quilt, with: .color(snow.lit(0.06).color()))
    ViewKit.rect(
      context,
      CGRect(x: Self.chimney.x - 1.2, y: Self.chimney.y - 0.8, width: 2.6, height: 0.9), snow)
    for index in 0..<9 {
      let x = wall.minX - 2 + CGFloat(index) * 3.6
      let length = 0.8 + 1.4 * CGFloat(ViewRhythm.hash(index, seed: 1152))
      var icicle = Path()
      icicle.move(to: CGPoint(x: x - 0.25, y: wall.minY + 1.3))
      icicle.addLine(to: CGPoint(x: x, y: wall.minY + 1.3 + length))
      icicle.addLine(to: CGPoint(x: x + 0.25, y: wall.minY + 1.3))
      icicle.closeSubpath()
      context.fill(icicle, with: .color(snow.lit(0.1).color(0.8)))
    }
    var drift = Path()
    drift.move(to: CGPoint(x: -45, y: base + 0.6))
    var x: CGFloat = -45
    var bump = 0
    while x < 145 {
      let rise = 0.4 + 1.2 * CGFloat(ViewRhythm.hash(bump, seed: 1153))
      drift.addQuadCurve(
        to: CGPoint(x: x + 12, y: base + 0.6), control: CGPoint(x: x + 6, y: base - rise))
      x += 12
      bump += 1
    }
    drift.addLine(to: CGPoint(x: 145, y: 65))
    drift.addLine(to: CGPoint(x: -45, y: 65))
    drift.closeSubpath()
    context.fill(drift, with: .color(snow.color()))
    context.fill(
      Path(ellipseIn: CGRect(x: 60, y: base + 0.8, width: 16, height: 2.4)),
      with: .color(snow.lit(-0.08).color()))
  }

  // MARK: - Near: a snowy bough and the balcony rail

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let snow = ViewKit.snow(look).mixed(with: colour, by: 0.4)
    var bough = Path()
    bough.move(to: CGPoint(x: -20, y: -8))
    bough.addQuadCurve(to: CGPoint(x: 24, y: 4), control: CGPoint(x: 4, y: -6))
    context.stroke(bough, with: .color(colour.lit(-0.1).color()), lineWidth: 0.9)
    for index in 0..<14 {
      let share = CGFloat(index) / 13
      let point = ViewKit.onWire(
        from: CGPoint(x: -20, y: -8), to: CGPoint(x: 24, y: 4), sag: -2.5, share: share)
      let size = 4.4 - 2.2 * share
      for side in [-1, 1] as [CGFloat] {
        var tuft = Path()
        tuft.move(to: CGPoint(x: point.x - size * 0.5, y: point.y))
        tuft.addLine(to: CGPoint(x: point.x + size * 0.3, y: point.y + side * size))
        tuft.addLine(to: CGPoint(x: point.x + size * 0.6, y: point.y))
        tuft.closeSubpath()
        context.fill(tuft, with: .color(colour.lit(side > 0 ? -0.04 : 0.04).color()))
      }
      ViewKit.circle(
        context, CGPoint(x: point.x, y: point.y - size * 0.55), size * 0.42, snow,
        index % 3 == 2 ? 0.6 : 0.9)
    }
    let wood = colour.mixed(with: ViewColour(0x5A3A26), by: look.isDark ? 0.25 : 0.4)
    ViewKit.ground(context, top: 56, colour: wood.lit(-0.1))
    ViewKit.rect(context, CGRect(x: -45, y: 50.4, width: 190, height: 1.4), wood)
    var post: CGFloat = -42
    while post < 145 {
      ViewKit.rect(context, CGRect(x: post, y: 51.8, width: 1.2, height: 4.4), wood.lit(-0.05))
      post += 9
    }
    var pile = Path()
    pile.move(to: CGPoint(x: -45, y: 50.6))
    var x: CGFloat = -45
    while x < 145 {
      let rise = 0.5 + 0.7 * CGFloat(ViewRhythm.hash(Int(x + 45), seed: 1161))
      pile.addQuadCurve(
        to: CGPoint(x: x + 7, y: 50.6), control: CGPoint(x: x + 3.5, y: 50.2 - rise))
      x += 7
    }
    pile.closeSubpath()
    context.fill(pile, with: .color(snow.color()))
  }
}
