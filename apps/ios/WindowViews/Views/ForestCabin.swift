import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// View 9: a cabin in the forest at night. Far: a mountain ridge furred with small pines, and
/// now and then a shooting star over it. Middle: a dense line of tall pines. Street: a clearing
/// with a log cabin, its windows warm and smoke curling from the chimney, a lantern on the porch,
/// a campfire between two stumps, an owl on a dead snag that blinks and turns its head, and a
/// deer stepping across now and then. Fireflies drift over the clearing. Near: a pine bough
/// swaying in from the top left and ferns along the bottom.
struct ForestCabin: ViewRecipe {
  static let clearing: CGFloat = 45
  static let cabin = CGRect(x: 20, y: 34.4, width: 30, height: 10.6)
  static let chimney = CGRect(x: 42, y: 25.4, width: 2.6, height: 6)
  static let lantern = CGPoint(x: 37.4, y: 38)
  static let fire = CGPoint(x: 70, y: 46.6)
  static let owl = CGPoint(x: 88.6, y: 25.8)
  static let windows: [ViewLitWindow] = [
    ViewLitWindow(id: 1801, rect: CGRect(x: 23, y: 37.4, width: 5.4, height: 4), plane: .street),
    ViewLitWindow(id: 1802, rect: CGRect(x: 41.6, y: 37.4, width: 5.4, height: 4), plane: .street),
  ]
  static let fireflies = ViewFireflies(
    count: 9, area: CGRect(x: 0, y: 30, width: 100, height: 16), seed: 18)
  static let shootingStar = ViewShootingStar(
    rhythm: ViewRhythm(seed: 871, slot: 45, chance: 0.5, length: 0.9...1.4))
  static let deer = ViewRhythm(seed: 881, slot: 80, chance: 0.5, length: 22...30)

  var moon: CGPoint { CGPoint(x: 70, y: -12) }
  var livePlanes: Set<ViewPlane> { [.far, .street, .near] }

  /// The forest's own colours: cool blue-green pines, a deep clear sky far from any town.
  static func grade(_ palette: inout ViewPalette, hour: ViewHour, share: Double) {
    let colours: [UInt32]
    switch hour {
    case .night: colours = [0x060A18, 0x142440, 0x2E4A6A, 0x1E3248, 0x14243A, 0x0E1A2A, 0x08101A]
    case .dusk: colours = [0x24204A, 0x5A4A86, 0xE88A70, 0x4A4870, 0x34344E, 0x24283A, 0x161A26]
    case .day: colours = [0x5A9AD0, 0x9CCAE6, 0xDDEFE8, 0x6A8A9A, 0x4A6A5A, 0x3A5440, 0x2A3E2E]
    case .morning:
      colours = [0x6E8CC0, 0xC0C4DC, 0xFFD6B0, 0x9AA0B4, 0x6A7A80, 0x4A5A54, 0x34403A]
    }
    palette.grade(colours, share: share)
    // Far from any town the stars come out thicker.
    palette.stars *= 1.4
    if palette.haze == 0, hour == .morning {
      palette.hazeColour = palette.horizon
      palette.haze = 0.3
    }
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

  // MARK: - Far and middle: ridges of pines

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    ViewKit.hills(
      context, base: 30, waves: [6, 9, 4, 11, 7, 5, 8, 10, 4], colour: colour.lit(0.04))
    if look.weather == .snow || look.hour == .night {
      // Snow, or moonlight, on the highest tops.
      let top = look.weather == .snow ? ViewKit.snow(look) : colour.lit(0.12)
      for (x, y) in [(-13.3, 21.0), (29, 19), (92.3, 22), (113.4, 20)] as [(CGFloat, CGFloat)] {
        var cap = Path()
        cap.move(to: CGPoint(x: x - 5, y: y + 3))
        cap.addQuadCurve(to: CGPoint(x: x + 5, y: y + 3), control: CGPoint(x: x, y: y - 3))
        cap.closeSubpath()
        context.fill(cap, with: .color(top.color(look.weather == .snow ? 0.8 : 0.5)))
      }
    }
    for index in 0..<40 {
      let x = -44 + CGFloat(index) * 4.7 + 2 * CGFloat(ViewRhythm.hash(index, seed: 891))
      let height = 4 + 3 * CGFloat(ViewRhythm.hash(index, seed: 892))
      ViewKit.pine(
        context, x: x, base: 31.4 + 1.6 * CGFloat(ViewRhythm.hash(index, seed: 893)),
        height: height,
        colour: colour.lit(-0.03), look: look)
    }
    ViewKit.ground(context, top: 35, colour: colour.lit(-0.03))
  }

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    for index in 0..<30 {
      let x = -44 + CGFloat(index) * 6.4 + 3 * CGFloat(ViewRhythm.hash(index, seed: 901))
      let height = 13 + 9 * CGFloat(ViewRhythm.hash(index, seed: 902))
      ViewKit.pine(
        context, x: x, base: 41, height: height,
        colour: colour.lit(index % 2 == 0 ? 0 : -0.04), look: look)
    }
    ViewKit.ground(context, top: 40, colour: colour.lit(-0.04))
  }

  // MARK: - Street: the clearing

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let base = Self.clearing
    let grass =
      look.weather == .snow
      ? ViewKit.snow(look).mixed(with: colour, by: 0.35)
      : colour.mixed(with: ViewColour(0x4A6A3A), by: look.isDark ? 0.12 : 0.3)
    // Two big pines flanking the clearing.
    for (x, height) in [(-10.0, 34.0), (106, 38), (126, 30)] as [(CGFloat, CGFloat)] {
      ViewKit.pine(
        context, x: x, base: base + 1, height: height, colour: colour.lit(-0.06), look: look)
    }
    // The dead snag the owl sits on.
    let snag = colour.lit(-0.1)
    ViewKit.rect(
      context,
      CGRect(x: Self.owl.x - 0.9, y: Self.owl.y + 0.4, width: 1.8, height: base - Self.owl.y), snag)
    var limb = Path()
    limb.move(to: CGPoint(x: Self.owl.x, y: Self.owl.y + 6))
    limb.addLine(to: CGPoint(x: Self.owl.x + 5, y: Self.owl.y + 2.6))
    limb.move(to: CGPoint(x: Self.owl.x, y: Self.owl.y + 10))
    limb.addLine(to: CGPoint(x: Self.owl.x - 4, y: Self.owl.y + 7.4))
    context.stroke(limb, with: .color(snag.color()), lineWidth: 0.6)
    ViewKit.ground(context, top: base, colour: grass)
    paintCabin(context, colour: colour, look: look)
    // The campfire's ring of stones and logs, and two stumps to sit on.
    let fire = Self.fire
    let stone = colour.lit(look.isDark ? 0.08 : 0.18)
    for index in 0..<7 {
      let x = fire.x - 3 + CGFloat(index)
      ViewKit.circle(
        context, CGPoint(x: x, y: fire.y + 0.4), 0.6, stone.lit(index % 2 == 0 ? 0 : -0.05))
    }
    let bark = colour.mixed(with: ViewColour(0x7A5034), by: look.isDark ? 0.18 : 0.4)
    var logs = Path()
    logs.move(to: CGPoint(x: fire.x - 2.4, y: fire.y))
    logs.addLine(to: CGPoint(x: fire.x + 2, y: fire.y - 1.6))
    logs.move(to: CGPoint(x: fire.x + 2.4, y: fire.y))
    logs.addLine(to: CGPoint(x: fire.x - 2, y: fire.y - 1.6))
    context.stroke(logs, with: .color(bark.color()), lineWidth: 0.6)
    for x in [fire.x - 7, fire.x + 6.4] {
      ViewKit.rect(context, CGRect(x: x, y: fire.y - 1.6, width: 2.2, height: 2), bark)
      context.fill(
        Path(ellipseIn: CGRect(x: x, y: fire.y - 2.1, width: 2.2, height: 1)),
        with: .color(bark.lit(0.15).color()))
    }
    // A woodpile against the cabin.
    for row in 0..<3 {
      for column in 0..<(4 - row) {
        let centre = CGPoint(
          x: Self.cabin.maxX + 1.4 + CGFloat(column) * 1.2 + CGFloat(row) * 0.6,
          y: base - 0.6 - CGFloat(row) * 1.1)
        ViewKit.circle(context, centre, 0.55, bark.lit(0.1))
      }
    }
  }

  private func paintCabin(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let cabin = Self.cabin
    let logs = colour.mixed(with: ViewColour(0x8A5A3A), by: look.isDark ? 0.22 : 0.45)
    ViewKit.rect(context, cabin, logs)
    // Log courses, each a round-ended band, and the ends crossing at the corners.
    var course = cabin.minY + 0.5
    while course < cabin.maxY {
      ViewKit.rect(
        context, CGRect(x: cabin.minX, y: course + 0.8, width: cabin.width, height: 0.18),
        logs.lit(-0.18), 0.9)
      for x in [cabin.minX - 0.8, cabin.maxX - 0.6] {
        ViewKit.circle(context, CGPoint(x: x + 0.7, y: course + 0.4), 0.55, logs.lit(0.1))
      }
      course += 1.1
    }
    ViewKit.rect(
      context, CGRect(x: cabin.minX, y: cabin.minY, width: cabin.width, height: 0.8),
      logs.lit(-0.2), 0.8)
    for window in Self.windows { ViewKit.windowFrame(context, window.rect, logs) }
    // The door, and the porch roof over it on two posts.
    ViewKit.rect(context, CGRect(x: 32.6, y: 37.8, width: 3.6, height: 7.2), logs.lit(-0.3))
    ViewKit.circle(context, CGPoint(x: 35.6, y: 41.6), 0.18, logs.lit(0.25))
    var porch = Path()
    porch.move(to: CGPoint(x: 29.6, y: 36.4))
    porch.addLine(to: CGPoint(x: 39.4, y: 36.4))
    porch.addLine(to: CGPoint(x: 40.2, y: 37.4))
    porch.addLine(to: CGPoint(x: 28.8, y: 37.4))
    porch.closeSubpath()
    context.fill(porch, with: .color(logs.lit(-0.15).color()))
    for x in [29.4, 39.2] as [CGFloat] {
      ViewKit.rect(context, CGRect(x: x, y: 37.4, width: 0.5, height: 7.6), logs.lit(-0.1))
    }
    // The chimney, then the steep roof over everything.
    let stone = colour.lit(look.isDark ? 0.06 : 0.15)
    ViewKit.rect(context, Self.chimney, stone)
    ViewKit.rect(
      context,
      CGRect(
        x: Self.chimney.minX - 0.3, y: Self.chimney.minY, width: Self.chimney.width + 0.6,
        height: 0.7),
      stone.lit(0.06))
    let roofColour = colour.mixed(with: ViewColour(0x5A3A2A), by: look.isDark ? 0.15 : 0.35)
    var roof = Path()
    roof.move(to: CGPoint(x: cabin.minX - 2.4, y: cabin.minY + 0.6))
    roof.addLine(to: CGPoint(x: cabin.midX, y: cabin.minY - 7.4))
    roof.addLine(to: CGPoint(x: cabin.maxX + 2.4, y: cabin.minY + 0.6))
    roof.closeSubpath()
    context.fill(roof, with: .color(roofColour.color()))
    var lit = Path()
    lit.move(to: CGPoint(x: cabin.midX, y: cabin.minY - 7.4))
    lit.addLine(to: CGPoint(x: cabin.maxX + 2.4, y: cabin.minY + 0.6))
    lit.addLine(to: CGPoint(x: cabin.midX + 1, y: cabin.minY + 0.6))
    lit.closeSubpath()
    context.fill(lit, with: .color(roofColour.lit(look.isDark ? 0.06 : 0.12).color()))
    // The chimney's part above the roof slope.
    ViewKit.rect(
      context,
      CGRect(x: Self.chimney.minX, y: Self.chimney.minY, width: Self.chimney.width, height: 2.6),
      stone)
    if look.weather == .snow {
      var cap = Path()
      cap.move(to: CGPoint(x: cabin.minX - 2.4, y: cabin.minY + 0.6))
      cap.addLine(to: CGPoint(x: cabin.midX, y: cabin.minY - 7.4))
      cap.addLine(to: CGPoint(x: cabin.maxX + 2.4, y: cabin.minY + 0.6))
      cap.addLine(to: CGPoint(x: cabin.maxX + 1.6, y: cabin.minY + 1.5))
      cap.addLine(to: CGPoint(x: cabin.midX, y: cabin.minY - 6))
      cap.addLine(to: CGPoint(x: cabin.minX - 1.6, y: cabin.minY + 1.5))
      cap.closeSubpath()
      context.fill(cap, with: .color(ViewKit.snow(look).color()))
    }
    // The lantern's hook under the porch roof.
    ViewKit.rect(
      context, CGRect(x: Self.lantern.x - 0.08, y: 37.4, width: 0.16, height: 0.6), logs.lit(-0.3))
  }

  // MARK: - Near: the pine bough and ferns

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let fern = colour.mixed(with: ViewColour(0x3A5A3A), by: look.isDark ? 0.1 : 0.3)
    ViewKit.ground(context, top: 58, colour: colour)
    for index in 0..<12 {
      let root = CGPoint(
        x: -30 + CGFloat(index) * 13 + 4 * CGFloat(ViewRhythm.hash(index, seed: 911)), y: 59)
      for side in [-1.0, 1.0] as [CGFloat] {
        for leaf in 0..<3 {
          let length = 5 - CGFloat(leaf) * 1.2
          var frond = Path()
          frond.move(to: root)
          frond.addQuadCurve(
            to: CGPoint(x: root.x + side * length, y: root.y - 3 - CGFloat(leaf) * 1.6),
            control: CGPoint(x: root.x + side * length * 0.3, y: root.y - 4 - CGFloat(leaf) * 1.6))
          context.stroke(
            frond, with: .color(fern.lit(leaf == 1 ? 0.04 : 0).color()), lineWidth: 0.8)
        }
      }
    }
  }
}
