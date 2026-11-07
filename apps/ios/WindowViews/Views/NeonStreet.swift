import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// View 11: a narrow city street in the rain. Far: a skyline of towers dotted with lit windows,
/// red lights on their roofs. Middle: apartment blocks and an elevated line on pillars, a lit
/// train sliding across it now and then. Street: a row of small shops, a ramen counter, an
/// izakaya with red lanterns, a bright corner shop and glowing vending machines, tall neon signs
/// of made-up glyphs that buzz, people under umbrellas, taxis, and the neon smeared down the wet
/// road. Near: the eave over the window, a red lantern swaying under it and drips off its edge.
struct NeonStreet: ViewRecipe {
  static let streetBase: CGFloat = 46
  static let roadway = ViewRoad(
    line: 51.4, kerb: streetBase,
    cars: ViewRhythm(seed: 1201, slot: 30, chance: 0.55, length: 5...7), length: 11,
    bodies: [0x2A2A30, 0xE8E4DC, 0x3A3A40, 0x5A2430, 0xE8C040])
  static let train = ViewRhythm(seed: 1211, slot: 40, chance: 0.7, length: 6...8)
  static let walkers = [
    ViewWalker(
      rhythm: ViewRhythm(seed: 1221, slot: 22, chance: 0.7, length: 12...16),
      from: CGPoint(x: -20, y: 46.6), to: CGPoint(x: 120, y: 46.6), height: 6.2,
      kinds: [.walker, .phone, .backpack], coats: [0x2A2A30, 0xE8E4DC, 0x8A3A4A, 0x3A5A8A]),
    ViewWalker(
      rhythm: ViewRhythm(seed: 1222, slot: 31, chance: 0.6, length: 13...18),
      from: CGPoint(x: -20, y: 47), to: CGPoint(x: 120, y: 47), height: 6.4,
      kinds: [.walker, .dog, .phone], coats: [0xC8A050, 0x4A6A3A, 0x2A2A30]),
  ]
  static let umbrellas: [UInt32] = [0xFF7AB0, 0xEAF2FA, 0xFFD166, 0x4FE8FF, 0x2A2A30]

  /// A tall sign of stacked glyph cells on a pole, standing above the shops.
  struct Sign: Sendable {
    var x: CGFloat
    var top: CGFloat
    var cells: Int
    var colour: UInt32

    static let width: CGFloat = 3.6
    static let cell: CGFloat = 3.8

    var rect: CGRect {
      CGRect(x: x, y: top, width: Self.width, height: CGFloat(cells) * Self.cell + 0.8)
    }
  }

  static let pink: UInt32 = 0xFF4FA3
  static let cyan: UInt32 = 0x4FE8FF
  static let amber: UInt32 = 0xFFB347
  static let violet: UInt32 = 0xB86BFF

  static let signs: [Sign] = [
    Sign(x: 0, top: 10, cells: 4, colour: pink), Sign(x: 16.4, top: 14, cells: 3, colour: cyan),
    Sign(x: 30, top: 8, cells: 5, colour: amber), Sign(x: 64, top: 14, cells: 3, colour: violet),
    Sign(x: 82, top: 9, cells: 4, colour: cyan), Sign(x: 98, top: 12, cells: 4, colour: pink),
    Sign(x: 114, top: 10, cells: 4, colour: amber), Sign(x: -24, top: 9, cells: 4, colour: cyan),
  ]
  static let buzz: [ViewRhythm] = (0..<8).map {
    ViewRhythm(seed: 1231 + UInt64($0), slot: 11, chance: 0.3, length: 0.5...1.5)
  }

  static let shops: [(x: CGFloat, width: CGFloat, top: CGFloat)] = [
    (-44, 38, 18), (-6, 26, 22), (20, 28, 20), (48, 28, 24), (76, 28, 19), (104, 41, 22),
  ]
  static let awnings: [UInt32] = [0x3A5A8A, 0x8A3A4A, 0x4A6A3A]
  static let ramen = CGPoint(x: 7, y: 33.4)
  static let cat = CGPoint(x: 90, y: 33.4)
  static let lanterns: [CGPoint] = [CGPoint(x: 23.6, y: 36.2), CGPoint(x: 44.4, y: 36.2)]
  static let vending: [CGRect] = [
    CGRect(x: 69.4, y: 38.4, width: 3.2, height: 7.6),
    CGRect(x: 73, y: 38.4, width: 3.2, height: 7.6),
  ]
  static let cornerShop = CGRect(x: 51, y: 38.6, width: 16, height: 7.4)

  var moon: CGPoint { CGPoint(x: 30, y: -12) }
  var livePlanes: Set<ViewPlane> { [.middle, .street, .near] }

  /// Violet city night with a magenta glow low down where the neon lights the cloud, and almost
  /// no stars.
  static func grade(_ palette: inout ViewPalette, hour: ViewHour, share: Double) {
    let colours: [UInt32]
    switch hour {
    case .night: colours = [0x0A0818, 0x22163A, 0x6A3A6A, 0x2A2440, 0x1E1A30, 0x161424, 0x0C0A16]
    case .dusk: colours = [0x2A2050, 0x6A4A8A, 0xE88A9A, 0x4A3E6A, 0x342C50, 0x262040, 0x16122A]
    case .day: colours = [0x7A8CA8, 0xA8B8CC, 0xD8DCE4, 0x9A9CAC, 0x7A7C8E, 0x5E6072, 0x424454]
    case .morning:
      colours = [0x7A80B8, 0xC0B0D0, 0xF8C8B8, 0xA8A0B8, 0x84809A, 0x66627C, 0x46425A]
    }
    palette.grade(colours, share: share)
    palette.stars *= 0.1
    palette.litShare = min(1, palette.litShare + 0.2)
    if palette.haze == 0 {
      palette.haze = 0.15
      palette.hazeColour = palette.horizon
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

  // MARK: - Far: the skyline

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let haze = colour.mixed(with: look.palette.horizon, by: 0.2)
    for index in 0..<20 {
      let x = -44 + CGFloat(index) * 9.6 + 3 * CGFloat(ViewRhythm.hash(index, seed: 1241))
      let width = 6 + 4 * CGFloat(ViewRhythm.hash(index, seed: 1242))
      let top = 4 + 20 * CGFloat(ViewRhythm.hash(index, seed: 1243))
      let tower = CGRect(x: x, y: top, width: width, height: 40 - top)
      ViewKit.rect(context, tower, haze.lit(index % 2 == 0 ? 0.03 : -0.02))
      ViewKit.rect(
        context, CGRect(x: x + width * 0.6, y: top, width: width * 0.4, height: 40 - top),
        haze.lit(look.isDark ? 0.05 : 0.1))
      if look.isDark {
        for dot in 0..<6 {
          let id = index * 10 + dot
          ViewKit.rect(
            context,
            CGRect(
              x: x + 0.6 + (width - 1.6) * CGFloat(ViewRhythm.hash(id, seed: 1244)),
              y: top + 1 + (38 - top) * CGFloat(ViewRhythm.hash(id, seed: 1245)), width: 0.6,
              height: 0.4), ViewPalette.lamp, 0.4 + 0.4 * ViewRhythm.hash(id, seed: 1246))
        }
        if index % 5 == 1 {
          ViewKit.circle(
            context, CGPoint(x: x + width / 2, y: top - 0.4), 0.3, ViewColour(0xFF3B3B), 0.9)
        }
      }
    }
    ViewKit.ground(context, top: 38, colour: haze.lit(-0.04))
  }

  // MARK: - Middle: blocks and the elevated line

  static let deck: CGFloat = 16

  static let middleWindows: [ViewLitWindow] = {
    var windows: [ViewLitWindow] = []
    for (block, x) in ([-30, 4, 100] as [CGFloat]).enumerated() {
      for floor in 0..<4 {
        for column in 0..<2 {
          let rect = CGRect(
            x: x + 2 + CGFloat(column) * 6, y: 20 + CGFloat(floor) * 5, width: 3, height: 2)
          let id = 1400 + block * 10 + floor * 2 + column
          windows.append(
            ViewLitWindow(id: id, rect: rect, plane: .middle, isTV: id % 5 == 2))
        }
      }
    }
    return windows
  }()

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    // Apartment blocks behind the line, balconies in rows.
    for (index, block)
      in ([(-34, 18, 4), (0, 16, 8), (60, 20, 2), (96, 18, 6), (120, 25, 0)]
      as [(CGFloat, CGFloat, CGFloat)]).enumerated()
    {
      let rect = CGRect(x: block.0, y: block.2, width: block.1, height: 44 - block.2)
      let wall = colour.lit(index % 2 == 0 ? 0.04 : -0.02)
      ViewKit.rect(context, rect, wall)
      var y = rect.minY + 4.6
      while y < 42 {
        ViewKit.rect(
          context, CGRect(x: rect.minX, y: y, width: rect.width, height: 0.4), wall.lit(-0.1))
        y += 5
      }
    }
    for window in Self.middleWindows { ViewKit.windowFrame(context, window.rect, colour) }
    // The line on its pillars: a concrete deck with a parapet and the overhead wire.
    let concrete = colour.lit(-0.12)
    var x: CGFloat = -40
    while x < 145 {
      ViewKit.rect(context, CGRect(x: x, y: Self.deck + 2.4, width: 2.2, height: 26), concrete)
      x += 17
    }
    ViewKit.rect(
      context, CGRect(x: -45, y: Self.deck, width: 190, height: 2.4), concrete.lit(0.04))
    ViewKit.rect(
      context, CGRect(x: -45, y: Self.deck + 2.4, width: 190, height: 0.5), concrete.lit(-0.15))
    var mast: CGFloat = -36
    while mast < 145 {
      ViewKit.rect(context, CGRect(x: mast, y: Self.deck - 9, width: 0.35, height: 9), concrete)
      ViewKit.rect(
        context, CGRect(x: mast - 1, y: Self.deck - 8.4, width: 2.4, height: 0.3), concrete)
      mast += 22
    }
    var wire = Path()
    wire.move(to: CGPoint(x: -45, y: Self.deck - 8.2))
    wire.addLine(to: CGPoint(x: 145, y: Self.deck - 8.2))
    context.stroke(wire, with: .color(concrete.lit(-0.2).color()), lineWidth: 0.12)
    ViewKit.ground(context, top: 42, colour: colour.lit(-0.06))
  }

  // MARK: - Street: the shops

  static let streetWindows: [ViewLitWindow] = {
    var windows: [ViewLitWindow] = []
    for (index, shop) in NeonStreet.shops.enumerated() {
      for column in 0..<2 {
        let width: CGFloat = 4.4
        let x = shop.x + shop.width * (column == 0 ? 0.22 : 0.62)
        windows.append(
          ViewLitWindow(
            id: 1500 + index * 2 + column,
            rect: CGRect(x: x, y: shop.top + 4, width: width, height: 3), plane: .street,
            isTV: (index + column) % 4 == 3))
      }
    }
    return windows
  }()

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let base = Self.streetBase
    let poleColour = colour.lit(-0.25)
    // Sign poles first, so the boards and the shops stand in front.
    for sign in Self.signs {
      ViewKit.rect(
        context, CGRect(x: sign.rect.midX - 0.3, y: sign.rect.maxY, width: 0.6, height: 10),
        poleColour)
    }
    for (index, shop) in Self.shops.enumerated() {
      let wall = colour.lit(index % 2 == 0 ? 0.05 : -0.01)
      let rect = CGRect(x: shop.x, y: shop.top, width: shop.width, height: base - shop.top)
      ViewKit.rect(context, rect, wall)
      // The roof's lip and a little water tank or unit on top.
      ViewKit.rect(
        context,
        CGRect(x: rect.minX - 0.4, y: rect.minY - 0.6, width: rect.width + 0.8, height: 0.6),
        wall.lit(0.06))
      ViewKit.rect(
        context, CGRect(x: rect.minX + rect.width * 0.7, y: rect.minY - 2.2, width: 3, height: 1.6),
        wall.lit(-0.1))
      // The front: dark inside, under a faded awning.
      ViewKit.rect(
        context, CGRect(x: rect.minX + 1.2, y: 38.6, width: rect.width - 2.4, height: base - 38.6),
        wall.lit(-0.35))
      let awning = colour.mixed(
        with: ViewColour(Self.awnings[index % Self.awnings.count]), by: look.isDark ? 0.3 : 0.5)
      ViewKit.rect(
        context, CGRect(x: rect.minX + 0.6, y: 37, width: rect.width - 1.2, height: 1.6), awning)
    }
    for window in Self.streetWindows { ViewKit.windowFrame(context, window.rect, colour) }
    // Dark boards for the neon: the tall signs and the two over the counters.
    let board = colour.lit(-0.4)
    for sign in Self.signs { ViewKit.rect(context, sign.rect, board) }
    for centre in [Self.ramen, Self.cat] {
      ViewKit.rect(
        context, CGRect(x: centre.x - 5, y: centre.y - 2, width: 10, height: 4), board)
    }
    // The vending machines' cases.
    for machine in Self.vending {
      ViewKit.rect(context, machine.insetBy(dx: -0.3, dy: -0.3), colour.lit(0.1))
    }
    // Utility poles and wires sagging over the street.
    let left = ViewKit.pole(context, x: 12, top: 2, base: base, colour: poleColour)
    let right = ViewKit.pole(context, x: 108, top: 4, base: base, colour: poleColour)
    for (a, b) in zip(left, right) {
      ViewKit.wire(context, from: a, to: b, sag: 2.4, colour: poleColour, width: 0.14)
    }
    for point in left.prefix(2) {
      ViewKit.wire(
        context, from: point, to: CGPoint(x: -45, y: point.y + 4), sag: 1.4, colour: poleColour,
        width: 0.14)
    }
    // Sidewalk, kerb and the wet road.
    ViewKit.rect(
      context, CGRect(x: -45, y: base, width: 190, height: 1.2),
      colour.lit(look.isDark ? 0.05 : 0.12))
    ViewKit.ground(context, top: base + 1.2, colour: colour.lit(-0.22))
  }

  // MARK: - Near: the eave

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    // The eave over the window, tiles end-on along its edge.
    var eave = Path()
    eave.move(to: CGPoint(x: 64, y: -50))
    eave.addLine(to: CGPoint(x: 145, y: -50))
    eave.addLine(to: CGPoint(x: 145, y: -1))
    eave.addLine(to: CGPoint(x: 70, y: -3))
    eave.closeSubpath()
    context.fill(eave, with: .color(colour.color()))
    var tile: CGFloat = 70
    while tile < 145 {
      let y = -3 + (tile - 70) / 75 * 2
      ViewKit.circle(context, CGPoint(x: tile + 1.2, y: y), 1.2, colour.lit(0.06))
      tile += 2.6
    }
    // A rail along the bottom, wet and catching the light.
    ViewKit.ground(context, top: 57, colour: colour)
    ViewKit.rect(context, CGRect(x: -45, y: 52.6, width: 190, height: 0.8), colour.lit(0.04))
    ViewKit.rect(
      context, CGRect(x: -45, y: 52.6, width: 190, height: 0.2),
      colour.lit(look.isDark ? 0.2 : 0.3))
    var post: CGFloat = -40
    while post < 145 {
      ViewKit.rect(context, CGRect(x: post, y: 53.4, width: 0.8, height: 4), colour)
      post += 10
    }
  }
}
