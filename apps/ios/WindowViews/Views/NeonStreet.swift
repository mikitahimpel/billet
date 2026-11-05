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

  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: break
    case .middle:
      ViewWindows.draw(Self.middleWindows, context, moment: moment)
      train(context, moment: moment)
    case .street:
      ViewWindows.draw(Self.streetWindows, context, moment: moment)
      reflections(context, moment: moment)
      shopLights(context, moment: moment)
      neon(context, moment: moment)
      for walker in Self.walkers { umbrellaWalker(walker, context, moment: moment) }
      Self.roadway.draw(context, moment: moment)
    case .near: lantern(context, moment: moment)
    }
  }

  /// How bright the neon is: off-white tubes by day, full glow after dark.
  private static func neonLevel(_ moment: ViewMoment) -> Double {
    0.15 + 0.85 * moment.lamps
  }

  /// A sign's brightness now: steady with a hum, now and then buzzing on and off.
  private static func signLevel(_ index: Int, moment: ViewMoment) -> Double {
    var level = neonLevel(moment) * (0.93 + 0.07 * sin(moment.now * 5 + Double(index)))
    if moment.lamps > 0, Self.buzz[index % Self.buzz.count].pass(at: moment.now) != nil,
      sin(moment.now * 47 + Double(index) * 3) > 0.1
    {
      level *= 0.2
    }
    return level
  }

  /// The glyphs: made-up characters of strokes, three or four to a cell.
  private func neon(_ context: GraphicsContext, moment: ViewMoment) {
    for (index, sign) in Self.signs.enumerated() {
      let level = Self.signLevel(index, moment: moment)
      let colour = ViewColour(sign.colour)
      let tube = colour.mixed(with: ViewColour(0xFFFFFF), by: 0.35)
      let rect = sign.rect
      ViewKit.glow(
        context, CGPoint(x: rect.midX, y: rect.midY), rect.height * 0.75, colour, 0.3 * level)
      for cell in 0..<sign.cells {
        let box = CGRect(
          x: rect.minX + 0.6, y: rect.minY + 0.6 + CGFloat(cell) * Sign.cell,
          width: Sign.width - 1.2, height: Sign.cell - 0.8)
        for stroke in Self.strokes(index * 10 + cell, in: box) {
          ViewKit.rect(context, stroke, tube, level)
        }
      }
    }
    // The ramen bowl: a bowl, chopsticks and steam.
    let ramenLevel = Self.signLevel(3, moment: moment)
    let ramen = Self.ramen
    let warm = ViewColour(Self.amber).mixed(with: ViewColour(0xFFFFFF), by: 0.3)
    var bowl = Path()
    bowl.move(to: CGPoint(x: ramen.x - 3.6, y: ramen.y - 0.2))
    bowl.addQuadCurve(
      to: CGPoint(x: ramen.x - 0.4, y: ramen.y - 0.2),
      control: CGPoint(x: ramen.x - 2, y: ramen.y + 2.6))
    bowl.closeSubpath()
    var chopsticks = Path()
    chopsticks.move(to: CGPoint(x: ramen.x - 2.6, y: ramen.y - 1.4))
    chopsticks.addLine(to: CGPoint(x: ramen.x - 0.2, y: ramen.y - 0.6))
    chopsticks.move(to: CGPoint(x: ramen.x - 2.2, y: ramen.y - 1.7))
    chopsticks.addLine(to: CGPoint(x: ramen.x + 0.2, y: ramen.y - 1))
    let style = StrokeStyle(lineWidth: 0.3, lineCap: .round)
    context.stroke(bowl, with: .color(warm.color(ramenLevel)), style: style)
    context.stroke(chopsticks, with: .color(warm.color(ramenLevel)), style: style)
    ViewKit.glow(context, ramen, 6, ViewColour(Self.amber), 0.25 * ramenLevel)
    for cell in 0..<2 {
      let box = CGRect(
        x: ramen.x + 0.6 + CGFloat(cell) * 2.2, y: ramen.y - 1.4, width: 1.8, height: 2.8)
      for stroke in Self.strokes(90 + cell, in: box) {
        ViewKit.rect(context, stroke, warm, ramenLevel)
      }
    }
    // The cat: a head with two ears and two eyes.
    let catLevel = Self.signLevel(5, moment: moment)
    let cat = Self.cat
    let pink = ViewColour(Self.pink).mixed(with: ViewColour(0xFFFFFF), by: 0.3)
    var head = Path()
    head.addEllipse(in: CGRect(x: cat.x - 1.5, y: cat.y - 1.1, width: 3, height: 2.4))
    head.move(to: CGPoint(x: cat.x - 1.3, y: cat.y - 0.5))
    head.addLine(to: CGPoint(x: cat.x - 1.1, y: cat.y - 1.9))
    head.addLine(to: CGPoint(x: cat.x - 0.4, y: cat.y - 1.05))
    head.move(to: CGPoint(x: cat.x + 1.3, y: cat.y - 0.5))
    head.addLine(to: CGPoint(x: cat.x + 1.1, y: cat.y - 1.9))
    head.addLine(to: CGPoint(x: cat.x + 0.4, y: cat.y - 1.05))
    context.stroke(head, with: .color(pink.color(catLevel)), style: style)
    // It winks now and then.
    let wink = sin(moment.now * 0.7) > 0.93
    ViewKit.circle(context, CGPoint(x: cat.x - 0.6, y: cat.y), 0.22, pink, catLevel)
    if !wink { ViewKit.circle(context, CGPoint(x: cat.x + 0.6, y: cat.y), 0.22, pink, catLevel) }
    ViewKit.glow(context, cat, 6, ViewColour(Self.pink), 0.25 * catLevel)
    for (cell, x) in [cat.x - 4.4, cat.x + 2.4].enumerated() {
      let box = CGRect(x: x, y: cat.y - 1.4, width: 1.8, height: 2.8)
      for stroke in Self.strokes(95 + cell, in: box) {
        ViewKit.rect(context, stroke, pink, catLevel)
      }
    }
  }

  /// The strokes of one made-up glyph inside `box`, picked by `seed`: never a real character.
  static func strokes(_ seed: Int, in box: CGRect) -> [CGRect] {
    let t: CGFloat = 0.32
    let all: [CGRect] = [
      CGRect(x: box.minX, y: box.minY, width: box.width, height: t),
      CGRect(x: box.minX + box.width * 0.1, y: box.midY - t / 2, width: box.width * 0.8, height: t),
      CGRect(x: box.midX - t / 2, y: box.minY, width: t, height: box.height),
      CGRect(x: box.minX, y: box.minY + box.height * 0.3, width: t, height: box.height * 0.7),
      CGRect(x: box.maxX - t, y: box.minY + box.height * 0.15, width: t, height: box.height * 0.5),
      CGRect(x: box.minX, y: box.maxY - t, width: box.width, height: t),
      CGRect(
        x: box.minX + box.width * 0.55, y: box.minY + box.height * 0.6, width: box.width * 0.45,
        height: t),
    ]
    var picked: [CGRect] = []
    for (index, stroke) in all.enumerated()
    where ViewRhythm.hash(seed * 7 + index, seed: 1251) < 0.5 {
      picked.append(stroke)
    }
    if picked.count < 2 { picked = [all[seed % 2 == 0 ? 0 : 1], all[2]] }
    return Array(picked.prefix(4))
  }

  /// The neon run down the wet road in broken, wobbling streaks.
  private func reflections(_ context: GraphicsContext, moment: ViewMoment) {
    let wet: Double =
      switch moment.look.weather {
      case .rain: 1
      case .fog: 0.45
      case .snow, .clear: 0.25
      }
    let top = Self.streetBase + 1.4
    for (index, sign) in Self.signs.enumerated() {
      let level = Self.signLevel(index, moment: moment) * wet
      guard level > 0.05 else { continue }
      let colour = ViewColour(sign.colour)
      let x = sign.rect.midX
      context.fill(
        Path(CGRect(x: x - 1.3, y: top, width: 2.6, height: 9)),
        with: .linearGradient(
          Gradient(colors: [colour.color(0.3 * level), colour.color(0)]),
          startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: top + 9)))
      for band in 0..<3 {
        let wobble = CGFloat(sin(moment.now * 2.6 + Double(index * 3 + band))) * 0.5
        ViewKit.rect(
          context,
          CGRect(
            x: x - 1.1 + wobble, y: top + 1 + CGFloat(band) * 2.4, width: 2.2, height: 0.35),
          colour.mixed(with: ViewColour(0xFFFFFF), by: 0.3), 0.45 * level)
      }
    }
  }

  /// The counters' light under their curtains, the corner shop's bright glass, the vending
  /// machines and the izakaya's lanterns.
  private func shopLights(_ context: GraphicsContext, moment: ViewMoment) {
    let lamps = moment.lamps
    let base = Self.streetBase
    let warm = ViewPalette.lamp
    // Warm light behind split curtains at the ramen counter and the izakaya.
    for (shop, curtain) in [(1, 0xF2EEE6), (2, 0x2A3A6A)] as [(Int, UInt32)] {
      let s = Self.shops[shop]
      let front = CGRect(x: s.x + 1.2, y: 38.6, width: s.width - 2.4, height: base - 38.6)
      ViewKit.rect(context, front, warm, 0.2 + 0.6 * lamps)
      let cloth = ViewColour(curtain).mixed(
        with: moment.palette.street, by: moment.look.isDark ? 0.35 : 0.15)
      let panels = 4
      let panelWidth = (front.width - 1) / CGFloat(panels)
      for panel in 0..<panels {
        ViewKit.rect(
          context,
          CGRect(
            x: front.minX + 0.5 + CGFloat(panel) * panelWidth + 0.15, y: front.minY,
            width: panelWidth - 0.3, height: 3.2), cloth)
      }
      ViewKit.glow(
        context, CGPoint(x: front.midX, y: base), front.width * 0.6, warm, 0.25 * lamps)
    }
    // The corner shop: cool white glass and shelves.
    let shop = Self.cornerShop
    let cool = ViewColour(0xE8F6FF)
    ViewKit.rect(context, shop, cool, 0.25 + 0.6 * lamps)
    for row in 0..<3 {
      ViewKit.rect(
        context,
        CGRect(
          x: shop.minX + 1, y: shop.minY + 1.4 + CGFloat(row) * 1.8, width: shop.width - 2,
          height: 0.4), moment.palette.street.lit(-0.1), 0.6)
    }
    ViewKit.glow(context, CGPoint(x: shop.midX, y: shop.midY), 14, cool, 0.2 * lamps)
    // The vending machines: lit panels with rows of drinks.
    let drinks = [0xFF4D5E, 0x3DDC84, 0xFFD166, 0x5BA8FF, 0xFF8A3D].map(ViewColour.init)
    for (index, machine) in Self.vending.enumerated() {
      let panel = CGRect(
        x: machine.minX + 0.3, y: machine.minY + 0.4, width: machine.width - 0.6, height: 3.6)
      ViewKit.rect(context, panel, cool, 0.35 + 0.6 * lamps)
      for row in 0..<3 {
        for slot in 0..<4 {
          ViewKit.rect(
            context,
            CGRect(
              x: panel.minX + 0.25 + CGFloat(slot) * 0.62,
              y: panel.minY + 0.35 + CGFloat(row) * 1.1,
              width: 0.36, height: 0.6), drinks[(index + row * 4 + slot) % drinks.count], 0.85)
        }
      }
      ViewKit.rect(
        context,
        CGRect(
          x: machine.minX + 0.8, y: machine.maxY - 1.6, width: machine.width - 1.6, height: 0.7),
        moment.palette.street.lit(-0.4))
      ViewKit.glow(
        context, CGPoint(x: machine.midX, y: machine.minY + 2.4), 6, cool, 0.3 * (0.3 + 0.7 * lamps)
      )
    }
    // Red paper lanterns at the izakaya, swaying a little.
    let red = ViewColour(0xE5503A)
    for (index, point) in Self.lanterns.enumerated() {
      let sway = CGFloat(sin(moment.now * 1.1 + Double(index) * 2)) * 0.25
      let centre = CGPoint(x: point.x + sway, y: point.y)
      paperLantern(context, centre: centre, size: 1.8, colour: red, lit: 0.2 + 0.8 * lamps)
    }
  }

  /// A round paper lantern: ribs across it, dark caps, glowing from inside.
  private func paperLantern(
    _ context: GraphicsContext, centre: CGPoint, size: CGFloat, colour: ViewColour, lit: Double
  ) {
    let body = CGRect(
      x: centre.x - size * 0.6, y: centre.y - size * 0.75, width: size * 1.2, height: size * 1.5)
    ViewKit.glow(context, centre, size * 3.4, colour, 0.35 * lit)
    context.fill(
      Path(ellipseIn: body),
      with: .color(colour.mixed(with: ViewPalette.lampCore, by: 0.3 * lit).color(0.6 + 0.4 * lit)))
    for rib in 1..<4 {
      let y = body.minY + body.height * CGFloat(rib) / 4
      ViewKit.rect(
        context,
        CGRect(
          x: body.minX + size * 0.12, y: y, width: body.width - size * 0.24, height: size * 0.05),
        colour.lit(-0.35), 0.6)
    }
    let cap = colour.lit(-0.6)
    ViewKit.rect(
      context,
      CGRect(
        x: centre.x - size * 0.3, y: body.minY - size * 0.12, width: size * 0.6, height: size * 0.18
      ), cap)
    ViewKit.rect(
      context,
      CGRect(
        x: centre.x - size * 0.3, y: body.maxY - size * 0.06, width: size * 0.6, height: size * 0.18
      ), cap)
  }

  /// Someone crossing, under an umbrella when it rains.
  private func umbrellaWalker(_ walker: ViewWalker, _ context: GraphicsContext, moment: ViewMoment)
  {
    guard let pass = walker.rhythm.pass(at: moment.now) else { return }
    walker.draw(context, moment: moment)
    guard moment.look.weather == .rain else { return }
    let feet = walker.point(pass)
    let facing: CGFloat = pass.variant < 0.5 ? 1 : -1
    let hex = Self.umbrellas[Int(pass.variant * 31) % Self.umbrellas.count]
    let isClear = hex == 0xEAF2FA
    let colour = ViewColour(hex).mixed(
      with: moment.palette.street, by: moment.look.isDark ? 0.35 : 0.15)
    let radius = walker.height * 0.44
    let centre = CGPoint(x: feet.x + facing * 0.4, y: feet.y - walker.height * 1.02)
    var handle = Path()
    handle.move(to: CGPoint(x: centre.x, y: centre.y - radius * 0.6))
    handle.addLine(to: CGPoint(x: centre.x, y: feet.y - walker.height * 0.55))
    context.stroke(handle, with: .color(moment.palette.street.lit(-0.3).color()), lineWidth: 0.15)
    var dome = Path()
    dome.move(to: CGPoint(x: centre.x - radius, y: centre.y))
    dome.addQuadCurve(
      to: CGPoint(x: centre.x + radius, y: centre.y),
      control: CGPoint(x: centre.x, y: centre.y - radius * 1.35))
    dome.addQuadCurve(
      to: CGPoint(x: centre.x - radius, y: centre.y),
      control: CGPoint(x: centre.x, y: centre.y - radius * 0.3))
    dome.closeSubpath()
    context.fill(dome, with: .color(colour.color(isClear ? 0.4 : 1)))
    // The neon caught on its top.
    var shine = context
    shine.clip(to: dome)
    shine.fill(
      Path(
        ellipseIn: CGRect(
          x: centre.x - radius * 0.2, y: centre.y - radius * 0.9, width: radius * 0.9,
          height: radius * 0.5)),
      with: .color(ViewColour(0xFFFFFF).color(0.2 + 0.15 * moment.lamps)))
  }

  /// Where the train's front is, and which way it is going.
  static let trainLength: CGFloat = 86

  static func trainHead(_ pass: ViewRhythm.Pass) -> (x: CGFloat, leftToRight: Bool) {
    let p = CGFloat(pass.progress)
    let leftToRight = pass.variant < 0.5
    let x = leftToRight ? -50 + (150 + trainLength + 50) * p : 150 - (150 + trainLength + 50) * p
    return (x, leftToRight)
  }

  /// A commuter train sliding along the line: four silver cars with a pink stripe and a strip of
  /// lit windows, a spark from the wire now and then.
  private func train(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = Self.train.pass(at: moment.now) else { return }
    let (head, leftToRight) = Self.trainHead(pass)
    let back: CGFloat = leftToRight ? -1 : 1
    let lamps = moment.lamps
    let silver = ViewColour(0xC8CCD4).mixed(
      with: moment.palette.middle, by: moment.look.isDark ? 0.55 : 0.25)
    let carLength: CGFloat = 20.5
    let top = Self.deck - 6.2
    for car in 0..<4 {
      let start = head + back * (CGFloat(car) * 21.5)
      let minX = leftToRight ? start - carLength : start
      let body = CGRect(x: minX, y: top, width: carLength, height: 6.2)
      context.fill(Path(roundedRect: body, cornerRadius: 1), with: .color(silver.color()))
      ViewKit.rect(
        context, CGRect(x: body.minX + 0.6, y: top + 1.2, width: carLength - 1.2, height: 2),
        silver.lit(-0.4))
      if lamps > 0 {
        ViewKit.rect(
          context, CGRect(x: body.minX + 0.6, y: top + 1.2, width: carLength - 1.2, height: 2),
          ViewPalette.lampCore, 0.8 * lamps)
      }
      ViewKit.rect(
        context, CGRect(x: body.minX, y: top + 4, width: carLength, height: 0.6),
        ViewColour(Self.pink).mixed(with: silver, by: 0.4))
      var pantograph = Path()
      pantograph.move(to: CGPoint(x: body.midX - 1.6, y: top))
      pantograph.addLine(to: CGPoint(x: body.midX, y: Self.deck - 8.2))
      pantograph.addLine(to: CGPoint(x: body.midX + 1.6, y: top))
      context.stroke(pantograph, with: .color(silver.lit(-0.4).color()), lineWidth: 0.15)
      if car == 1, sin(moment.now * 9) > 0.96 {
        ViewKit.glow(
          context, CGPoint(x: body.midX, y: Self.deck - 8.2), 2.4, ViewColour(0xBFE8FF), 0.9)
      }
    }
    if lamps > 0 {
      ViewKit.glow(
        context, CGPoint(x: head, y: top + 4.6), 4, ViewPalette.lampCore, 0.6 * lamps)
      ViewKit.glow(
        context, CGPoint(x: head + back * (3 * 21.5 + carLength), y: top + 4.6), 2,
        ViewColour(0xFF3B3B), 0.6 * lamps)
    }
  }

  /// The lantern under the eave, swinging in the wet wind, and drips off the eave's edge.
  private func lantern(_ context: GraphicsContext, moment: ViewMoment) {
    let wind = moment.look.weather == .rain ? 1.6 : 1
    let swing = (0.6 * sin(moment.now * 0.9) + 0.3 * sin(moment.now * 2.1 + 1)) * wind
    let hook = CGPoint(x: 90, y: -2.4)
    let length: CGFloat = 6
    let angle = swing * 0.12
    let centre = CGPoint(
      x: hook.x + CGFloat(sin(angle)) * length, y: hook.y + CGFloat(cos(angle)) * length)
    var cord = Path()
    cord.move(to: hook)
    cord.addLine(to: centre)
    context.stroke(cord, with: .color(moment.palette.near.lit(-0.3).color()), lineWidth: 0.2)
    paperLantern(
      context, centre: CGPoint(x: centre.x, y: centre.y + 2.6), size: 3.2,
      colour: ViewColour(0xE5503A), lit: 0.25 + 0.75 * moment.lamps)
    guard moment.look.weather == .rain else { return }
    for drip in 0..<4 {
      let period = 1.3 + 0.4 * ViewRhythm.hash(drip, seed: 1261)
      let p = (moment.now / period + ViewRhythm.hash(drip, seed: 1262))
        .truncatingRemainder(dividingBy: 1)
      let x = 74 + CGFloat(drip) * 9 + 4 * CGFloat(ViewRhythm.hash(drip, seed: 1263))
      let edge = -3 + (x - 70) / 75 * 2 + 1
      ViewKit.rect(
        context, CGRect(x: x, y: edge + CGFloat(p * p) * 60, width: 0.2, height: 1),
        ViewColour(0xDDE6F0), 0.5)
    }
  }

  func headlight(at now: Double) -> ViewHeadlight? { Self.roadway.headlight(at: now) }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if let pass = Self.train.pass(at: moment.now) {
      let (head, leftToRight) = Self.trainHead(pass)
      let minX = leftToRight ? head - Self.trainLength : head
      let maxX = minX + Self.trainLength
      let x = min(max((minX + maxX) / 2, 4), 96)
      if maxX > 0, minX < 100 {
        return ViewInterest(
          point: CGPoint(x: x, y: Self.deck - 3), plane: .middle, paw: false, id: pass.index)
      }
    }
    for walker in Self.walkers {
      if let interest = walker.interest(at: moment.now) { return interest }
    }
    return Self.roadway.interest(at: moment.now)
  }
}
