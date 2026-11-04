import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// View 10: snowy mountains under the moon. Far: a wall of peaks, their snow lit on the side
/// towards the moon and blue in shadow, a paler range behind, and now and then a shooting star.
/// Middle: a valley of snowy pines and a gondola's cable strung over it on two pylons, a cabin
/// gliding along it, lit after dark. Street: a wooden chalet with warm windows, fairy lights under
/// its eave and smoke from the chimney, a fox trotting over the snow now and then. Near: a snowy
/// pine bough hanging in and a balcony rail with snow along it.
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

  /// Moonlit blue at night, lilac at dusk, a clear bright sky by day, and far more stars than
  /// over any town.
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
    // A paler range further off, lost in the moonlit air.
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
      // The snow cap: deep down the slopes, its lower edge in teeth.
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
      // The face towards the moon.
      var face = Path()
      face.move(to: apex)
      face.addLine(to: CGPoint(x: peak.right + 2, y: base))
      face.addLine(to: CGPoint(x: apex.x + 2, y: base))
      face.closeSubpath()
      var litCap = cap
      litCap.clip(to: field)
      litCap.fill(face, with: .color(lit.color()))
      // Rock ridges running down from the summit.
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
    // The snowfield at the feet of the peaks.
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
    // Rows of snowy pines down the valley.
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
    // The cable, two ropes a little apart.
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
    // Pines on either side of the chalet.
    let pines: [CGFloat] = [4, 14, 26, 40, 92, 104, 118]
    for (index, x) in pines.enumerated() {
      ViewKit.pine(
        context, x: x, base: base + 0.4,
        height: 13 + 6 * CGFloat(ViewRhythm.hash(index, seed: 1151)),
        colour: colour.lit(index % 2 == 0 ? 0 : -0.04), look: snowy)
    }
    // The chalet: dark timber walls, a steep roof under a deep quilt of snow.
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
    // The balcony across the front.
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
    // The chimney, then the roof over it.
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
    // The gable's own boards, inside the roof line.
    var gable = Path()
    gable.move(to: CGPoint(x: wall.minX + 0.5, y: wall.minY + 0.4))
    gable.addLine(to: CGPoint(x: apex.x, y: apex.y + 2.4))
    gable.addLine(to: CGPoint(x: wall.maxX - 0.5, y: wall.minY + 0.4))
    gable.closeSubpath()
    context.fill(gable, with: .color(wood.lit(0.04).color()))
    ViewKit.windowFrame(context, Self.chaletWindows[4].rect, wood)
    // A thick quilt of snow on the roof, rounded at the eaves, with a few icicles.
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
    // Deep snow over the ground, a trodden path to the door, and its drifts.
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
    // A pine bough hanging in from the top left, its needles in tufts, snow along the top.
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
    // The balcony rail along the bottom of the window, snow piled on it.
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
