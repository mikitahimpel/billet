import CoreGraphics
import Foundation
import Pet
import SwiftUI

struct RooftopsDusk: ViewRecipe {
  /// The building across the street: its left edge and the top of its cornice.
  static let facadeLeft: CGFloat = 56
  static let facadeTop: CGFloat = 30
  static let chimney = CGPoint(x: 17.9, y: 20.2)
  static let roofCat = ViewRoofCat(
    rhythm: ViewRhythm(seed: 801, slot: 130, chance: 0.55, length: 40...70),
    left: CGPoint(x: 39, y: 28), ridge: CGPoint(x: 47, y: 28), right: CGPoint(x: 55, y: 28))
  static let swifts = ViewRhythm(seed: 811, slot: 50, chance: 0.7, length: 18...28)
  static let waterer = ViewRhythm(seed: 821, slot: 80, chance: 0.55, length: 12...18)

  var moon: CGPoint { CGPoint(x: 30, y: -12) }
  var livePlanes: Set<ViewPlane> { [.middle, .street] }

  static func grade(_ palette: inout ViewPalette, hour: ViewHour, share: Double) {
    let colours: [UInt32]
    switch hour {
    case .dusk: colours = [0x2E2A5E, 0x8A6AA8, 0xFFB08A, 0x8A7A9E, 0x5E5A80, 0x423C5E, 0x262238]
    case .night: colours = [0x0C1028, 0x252A56, 0x5A4A72, 0x2C2E50, 0x20223E, 0x171830, 0x0E0E1E]
    case .day: colours = [0x6AA6DA, 0xA8D0EA, 0xF4E6D2, 0xB8BCCC, 0x9098AE, 0x707890, 0x4E5268]
    case .morning:
      colours = [0x8494CC, 0xDCC0D4, 0xFFD2B0, 0xC0B4C4, 0x948AA4, 0x726A86, 0x4E4660]
    }
    palette.grade(colours, share: share)
    // A city sky: fewer stars, a little haze over the far roofs.
    palette.stars *= 0.4
    if palette.haze == 0 {
      palette.hazeColour = palette.horizon
      palette.haze = 0.15
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

  private static func stone(_ colour: ViewColour, look: ViewLook) -> ViewColour {
    colour.mixed(with: ViewColour(0xE8D8C0), by: look.isDark ? 0.12 : 0.32)
  }

  private static func zinc(_ colour: ViewColour, look: ViewLook) -> ViewColour {
    colour.mixed(with: ViewColour(0x7C8CA4), by: look.isDark ? 0.15 : 0.35)
  }

  // MARK: - Far: the skyline

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let haze = colour.mixed(with: look.palette.horizon, by: 0.25)
    for index in 0..<26 {
      let x = -44 + CGFloat(index) * 7.4
      let top = 29 + 4 * CGFloat(ViewRhythm.hash(index, seed: 831))
      ViewKit.rect(
        context, CGRect(x: x, y: top, width: 7.6, height: 38 - top),
        haze.lit(Double(index % 3) * 0.02))
    }
    let dome = CGPoint(x: 74, y: 22)
    ViewKit.rect(context, CGRect(x: dome.x - 5, y: dome.y, width: 10, height: 9), haze)
    context.fill(
      Path(ellipseIn: CGRect(x: dome.x - 5.4, y: dome.y - 5.4, width: 10.8, height: 10.8)),
      with: .color(haze.color()))
    ViewKit.rect(context, CGRect(x: dome.x - 3.4, y: dome.y, width: 0.4, height: 6), haze.lit(0.06))
    ViewKit.rect(context, CGRect(x: dome.x + 3.0, y: dome.y, width: 0.4, height: 6), haze.lit(0.06))
    ViewKit.rect(context, CGRect(x: dome.x - 0.8, y: dome.y - 8, width: 1.6, height: 3), haze)
    ViewKit.rect(context, CGRect(x: dome.x - 0.2, y: dome.y - 10, width: 0.4, height: 2), haze)
    let spire = CGPoint(x: 18, y: 12)
    ViewKit.rect(context, CGRect(x: spire.x - 2, y: spire.y + 8, width: 4, height: 12), haze)
    var cone = Path()
    cone.move(to: CGPoint(x: spire.x - 2.2, y: spire.y + 8.2))
    cone.addLine(to: CGPoint(x: spire.x, y: spire.y))
    cone.addLine(to: CGPoint(x: spire.x + 2.2, y: spire.y + 8.2))
    cone.closeSubpath()
    context.fill(cone, with: .color(haze.lit(-0.03).color()))
    ViewKit.rect(context, CGRect(x: spire.x - 0.1, y: spire.y - 1.6, width: 0.2, height: 1.6), haze)
    if look.isDark {
      for index in 0..<40 {
        let x = -40 + 180 * CGFloat(ViewRhythm.hash(index, seed: 832))
        let y = 31 + 6 * CGFloat(ViewRhythm.hash(index, seed: 833))
        ViewKit.rect(
          context, CGRect(x: x, y: y, width: 0.5, height: 0.6), ViewPalette.lamp,
          0.35 + 0.4 * ViewRhythm.hash(index, seed: 834))
      }
    }
    ViewKit.ground(context, top: 37, colour: haze.lit(-0.03))
  }

  // MARK: - Middle: zinc roofs and chimney pots

  static let blocks: [(x: CGFloat, width: CGFloat, top: CGFloat)] = [
    (-44, 26, 26), (-16, 22, 29), (8, 26, 25), (36, 22, 28), (60, 28, 24), (90, 24, 27),
    (116, 28, 25),
  ]

  static let middleWindows: [ViewLitWindow] = {
    var windows: [ViewLitWindow] = []
    for (index, block) in blocks.enumerated() {
      let count = Int(block.width / 8)
      for slot in 0..<count {
        let x = block.x + 3 + CGFloat(slot) * (block.width - 6) / CGFloat(max(count - 1, 1)) - 0.8
        windows.append(
          ViewLitWindow(
            id: 1000 + index * 10 + slot,
            rect: CGRect(x: x, y: block.top + 2.4, width: 1.6, height: 2), plane: .middle))
        windows.append(
          ViewLitWindow(
            id: 1005 + index * 10 + slot,
            rect: CGRect(x: x - 0.2, y: block.top + 9.6, width: 2, height: 3.2), plane: .middle,
            isTV: (index + slot) % 5 == 3))
      }
    }
    return windows
  }()

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let stone = Self.stone(colour, look: look)
    let zinc = Self.zinc(colour, look: look)
    for (index, block) in Self.blocks.enumerated() {
      let eave = block.top + 7
      ViewKit.rect(
        context, CGRect(x: block.x, y: eave, width: block.width, height: 50 - eave),
        stone.lit(Double(index % 2) * 0.03))
      ViewKit.rect(
        context, CGRect(x: block.x - 0.3, y: eave - 0.2, width: block.width + 0.6, height: 0.6),
        stone.lit(0.08))
      var roof = Path()
      roof.move(to: CGPoint(x: block.x, y: eave))
      roof.addLine(to: CGPoint(x: block.x + 2, y: block.top))
      roof.addLine(to: CGPoint(x: block.x + block.width - 2, y: block.top))
      roof.addLine(to: CGPoint(x: block.x + block.width, y: eave))
      roof.closeSubpath()
      context.fill(roof, with: .color(zinc.color()))
      var seams = context
      seams.clip(to: roof)
      var x = block.x + 0.6
      while x < block.x + block.width {
        seams.fill(
          Path(CGRect(x: x, y: block.top, width: 0.1, height: 7)),
          with: .color(zinc.lit(0.1).color(0.5)))
        x += 1.2
      }
      seams.fill(
        Path(CGRect(x: block.x + block.width - 4, y: block.top, width: 4, height: 7)),
        with: .color(zinc.lit(look.isDark ? 0.05 : 0.12).color(0.6)))
      ViewKit.rect(
        context,
        CGRect(x: block.x + 1.6, y: block.top - 0.4, width: block.width - 3.2, height: 0.4),
        zinc.lit(0.1))
      // Not on the roof the cat walks.
      if index != 3 {
        let stackX = block.x + block.width * (index % 2 == 0 ? 0.3 : 0.62)
        ViewKit.rect(
          context, CGRect(x: stackX, y: block.top - 3, width: 4.4, height: 3), stone.lit(-0.05))
        ViewKit.rect(
          context, CGRect(x: stackX - 0.2, y: block.top - 3.3, width: 4.8, height: 0.4),
          stone.lit(0.04))
        let pot = ViewColour(0xC0603A).mixed(with: colour, by: look.isDark ? 0.55 : 0.25)
        for slot in 0..<3 {
          ViewKit.rect(
            context,
            CGRect(
              x: stackX + 0.4 + CGFloat(slot) * 1.35, y: block.top - 4.6, width: 0.8, height: 1.3),
            pot.lit(slot == 1 ? 0.06 : 0))
        }
      }
      if index % 3 == 1 {
        let ax = block.x + block.width * 0.8
        var mast = Path()
        mast.move(to: CGPoint(x: ax, y: block.top))
        mast.addLine(to: CGPoint(x: ax, y: block.top - 6))
        for (row, half) in [(0.0, 2.0), (1.2, 1.5), (2.4, 1.0)] as [(CGFloat, CGFloat)] {
          mast.move(to: CGPoint(x: ax - half, y: block.top - 6 + row))
          mast.addLine(to: CGPoint(x: ax + half, y: block.top - 6 + row))
        }
        context.stroke(mast, with: .color(colour.lit(-0.2).color()), lineWidth: 0.15)
      }
      if look.weather == .snow {
        ViewKit.rect(
          context,
          CGRect(x: block.x + 1.8, y: block.top - 0.5, width: block.width - 3.6, height: 0.6),
          ViewKit.snow(look), 0.85)
      }
    }
    for window in Self.middleWindows {
      if window.rect.width < 1.8 {
        ViewKit.rect(
          context, window.rect.insetBy(dx: -0.6, dy: -0.6).offsetBy(dx: 0, dy: -0.2),
          stone.lit(0.02))
        context.fill(
          Path(
            ellipseIn: CGRect(
              x: window.rect.minX - 0.8, y: window.rect.minY - 1.6, width: window.rect.width + 1.6,
              height: 1.8)), with: .color(zinc.lit(-0.05).color()))
      }
      ViewKit.windowFrame(context, window.rect, stone)
    }
  }

  // MARK: - Street: the building across

  static let streetWindows: [ViewLitWindow] = {
    var windows: [ViewLitWindow] = []
    for floor in 0..<2 {
      for column in 0..<10 {
        let rect = CGRect(
          x: facadeLeft + 3 + CGFloat(column) * 9, y: facadeTop + 4 + CGFloat(floor) * 10,
          width: 4.2, height: 6.6)
        windows.append(
          ViewLitWindow(
            id: 1200 + floor * 10 + column, rect: rect, plane: .street,
            isTV: (floor * 3 + column) % 7 == 4))
      }
    }
    return windows
  }()

  static var watererWindow: CGRect { streetWindows[2].rect }

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let stone = Self.stone(colour, look: look)
    let zinc = Self.zinc(colour, look: look)
    let left = Self.facadeLeft
    let top = Self.facadeTop
    var roof = Path()
    roof.move(to: CGPoint(x: left, y: top))
    roof.addLine(to: CGPoint(x: left + 2.4, y: top - 6))
    roof.addLine(to: CGPoint(x: 150, y: top - 6))
    roof.addLine(to: CGPoint(x: 150, y: top))
    roof.closeSubpath()
    context.fill(roof, with: .color(zinc.color()))
    for column in 0..<9 {
      let x = left + 6 + CGFloat(column) * 9
      ViewKit.rect(context, CGRect(x: x - 1.4, y: top - 4.6, width: 2.8, height: 3.4), stone)
      ViewKit.rect(
        context, CGRect(x: x - 0.9, y: top - 4, width: 1.8, height: 2.4), colour.lit(-0.3))
    }
    if look.weather == .snow {
      ViewKit.rect(
        context, CGRect(x: left + 2.4, y: top - 6.5, width: 100, height: 0.7), ViewKit.snow(look),
        0.85)
    }
    ViewKit.rect(context, CGRect(x: left, y: top, width: 150 - left, height: 60 - top), stone)
    ViewKit.rect(
      context, CGRect(x: left - 0.6, y: top, width: 150 - left, height: 1.2), stone.lit(0.08))
    for floor in 0..<2 {
      ViewKit.rect(
        context,
        CGRect(x: left, y: top + 12.4 + CGFloat(floor) * 10, width: 150 - left, height: 0.5),
        stone.lit(-0.06))
    }
    ViewKit.rect(context, CGRect(x: left, y: top, width: 1.4, height: 60 - top), stone.lit(0.06))
    for window in Self.streetWindows {
      ViewKit.windowFrame(context, window.rect, stone)
      let shutter = colour.mixed(with: ViewColour(0x5A7A8A), by: look.isDark ? 0.2 : 0.45)
      for x in [window.rect.minX - 1.6, window.rect.maxX + 0.5] {
        ViewKit.rect(
          context, CGRect(x: x, y: window.rect.minY, width: 1.1, height: window.rect.height),
          shutter)
      }
    }
    ViewKit.ground(context, top: 50, colour: colour.lit(-0.25))
  }

  /// Drawn over the lit windows.
  func balconies(_ context: GraphicsContext, moment: ViewMoment) {
    let iron = moment.palette.street.lit(-0.45)
    let bloom = ViewColour(0xE0303A).mixed(
      with: moment.palette.street, by: moment.look.isDark ? 0.5 : 0.15)
    let leaves = ViewColour(0x3F7A4E).mixed(
      with: moment.palette.street, by: moment.look.isDark ? 0.55 : 0.3)
    for floor in 0..<2 {
      let y = Self.facadeTop + 10.6 + CGFloat(floor) * 10
      let from = Self.facadeLeft + 1.4
      var rail = Path()
      rail.move(to: CGPoint(x: from, y: y - 2.6))
      rail.addLine(to: CGPoint(x: 150, y: y - 2.6))
      rail.move(to: CGPoint(x: from, y: y))
      rail.addLine(to: CGPoint(x: 150, y: y))
      var x = from
      while x < 146 {
        rail.move(to: CGPoint(x: x, y: y - 2.6))
        rail.addLine(to: CGPoint(x: x, y: y))
        x += 1.1
      }
      context.stroke(rail, with: .color(iron.color()), lineWidth: 0.16)
      for column in 0..<10 {
        let bx = Self.facadeLeft + 2.6 + CGFloat(column) * 9
        ViewKit.rect(context, CGRect(x: bx, y: y - 1.6, width: 5, height: 1.2), iron.lit(0.25))
        for bud in 0..<4 {
          let point = CGPoint(x: bx + 0.7 + CGFloat(bud) * 1.2, y: y - 2)
          ViewKit.circle(context, point, 0.7, bud % 2 == 0 ? leaves : leaves.lit(0.05))
          if (bud + column) % 3 != 2 {
            ViewKit.circle(context, CGPoint(x: point.x + 0.2, y: point.y - 0.5), 0.45, bloom)
          }
        }
      }
    }
    ViewLightString(
      from: CGPoint(x: Self.facadeLeft + 1.4, y: Self.facadeTop + 7.6),
      to: CGPoint(x: Self.facadeLeft + 44, y: Self.facadeTop + 7.6), sag: 0.8, count: 14, seed: 3
    ).draw(context, moment: moment)
  }

  // MARK: - Near: the window's own rail

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let iron = colour.lit(-0.15)
    var rail = Path()
    for y in [50.4, 55.6] as [CGFloat] {
      rail.move(to: CGPoint(x: -45, y: y))
      rail.addLine(to: CGPoint(x: 145, y: y))
    }
    var x: CGFloat = -44
    while x < 145 {
      rail.move(to: CGPoint(x: x, y: 50.4))
      rail.addLine(to: CGPoint(x: x, y: 55.6))
      rail.addEllipse(in: CGRect(x: x + 0.5, y: 51.6, width: 2, height: 2))
      x += 3
    }
    context.stroke(rail, with: .color(iron.color()), lineWidth: 0.3)
    ViewKit.rect(context, CGRect(x: -45, y: 49.8, width: 190, height: 0.7), iron)
    let pot = ViewColour(0xB8583A).mixed(with: colour, by: look.isDark ? 0.6 : 0.3)
    var body = Path()
    body.move(to: CGPoint(x: 4, y: 45))
    body.addLine(to: CGPoint(x: 14, y: 45))
    body.addLine(to: CGPoint(x: 13, y: 50))
    body.addLine(to: CGPoint(x: 5, y: 50))
    body.closeSubpath()
    context.fill(body, with: .color(pot.color()))
    ViewKit.rect(context, CGRect(x: 3.6, y: 44.4, width: 10.8, height: 1.2), pot.lit(0.06))
    let leaves = colour.mixed(with: ViewColour(0x3F7A4E), by: look.isDark ? 0.15 : 0.4)
    let bloom = ViewColour(0xE0303A).mixed(with: colour, by: look.isDark ? 0.45 : 0.1)
    for index in 0..<9 {
      let px = 4.6 + CGFloat(index) * 1.1
      let py = 43.4 - 2 * CGFloat(ViewRhythm.hash(index, seed: 841))
      ViewKit.circle(context, CGPoint(x: px, y: py), 1.3, leaves.lit(index % 2 == 0 ? 0.04 : 0))
    }
    for index in 0..<4 {
      let centre = CGPoint(
        x: 5.6 + CGFloat(index) * 2.4, y: 39.8 - 1.4 * CGFloat(ViewRhythm.hash(index, seed: 842)))
      for petal in 0..<5 {
        let angle = Double(petal) / 5 * 2 * Double.pi
        ViewKit.circle(
          context,
          CGPoint(x: centre.x + CGFloat(cos(angle)) * 0.6, y: centre.y + CGFloat(sin(angle)) * 0.6),
          0.55, bloom)
      }
    }
    ViewKit.ground(context, top: 57, colour: colour)
  }
}
