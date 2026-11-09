import CoreGraphics
import Foundation
import Pet
import SwiftUI

struct AutumnPark: ViewRecipe {
  static let pathTop: CGFloat = 46
  static let pathBase: CGFloat = 49
  static let lamp = ViewStreetLamp(head: CGPoint(x: 58, y: 31), ground: pathBase)
  static let pond = CGRect(x: 6, y: 40.4, width: 44, height: 4.4)
  static let ducks = ViewRhythm(seed: 901, slot: 60, chance: 0.7, length: 30...50)
  static let squirrel = ViewRhythm(seed: 911, slot: 45, chance: 0.6, length: 8...12)
  /// The street tree the squirrel climbs: its trunk's centre and how high it goes.
  static let climbTree = (x: CGFloat(4), base: CGFloat(49), top: CGFloat(34))
  static let walker = ViewWalker(
    rhythm: ViewRhythm(seed: 921, slot: 50, chance: 0.6, length: 24...32),
    from: CGPoint(x: -25, y: 48), to: CGPoint(x: 125, y: 48), height: 6.6,
    kinds: [.dog, .walker, .phone, .dog, .backpack],
    coats: [0xC8783A, 0x8A3A4A, 0xE0C8A0, 0x4A6A5A, 0xD8B040])
  static let jogger = ViewWalker(
    rhythm: ViewRhythm(seed: 931, slot: 40, chance: 0.5, length: 8...11),
    from: CGPoint(x: -25, y: 47.2), to: CGPoint(x: 125, y: 47.2), height: 6.2,
    kinds: [.walker], coats: [0xFF6A8A, 0x5AB0E0, 0xF2F0EA])

  var moon: CGPoint { CGPoint(x: 70, y: -12) }
  var livePlanes: Set<ViewPlane> { [.middle, .street, .near] }

  static func grade(_ palette: inout ViewPalette, hour: ViewHour, share: Double) {
    let colours: [UInt32]
    switch hour {
    case .day: colours = [0x6C9ED0, 0xA8CCE4, 0xF2E2C8, 0xB0A890, 0x9A7A50, 0x6E5A3E, 0x4A3A2A]
    case .dusk: colours = [0x2E2A58, 0x7A5C94, 0xF8A070, 0x7A6278, 0x5C4658, 0x40323E, 0x261E26]
    case .night: colours = [0x0A1020, 0x1E2A48, 0x44506E, 0x283048, 0x1E2236, 0x161828, 0x0E0E18]
    case .morning:
      colours = [0x7A90C4, 0xC8C4D8, 0xFFD8B0, 0xC0B0A0, 0xA08468, 0x76604A, 0x4E4034]
    }
    palette.grade(colours, share: share)
    if palette.haze == 0, hour == .day || hour == .morning {
      palette.hazeColour = palette.horizon
      palette.haze = 0.18
    }
  }

  static let foliage: [UInt32] = [0xE07A2E, 0xC8452E, 0xE8B03A, 0xB86A2A, 0xD8602A]

  static func leafColour(_ index: Int, plane: ViewColour, look: ViewLook) -> ViewColour {
    plane.mixed(
      with: ViewColour(foliage[index % foliage.count]), by: look.isDark ? 0.3 : 0.62)
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

  // MARK: - Far: the city through the trees

  private func paintFar(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let city = colour.mixed(with: look.palette.horizon, by: 0.35)
    for index in 0..<16 {
      let x = -40 + CGFloat(index) * 11.5 + 4 * CGFloat(ViewRhythm.hash(index, seed: 941))
      let top = 18 + 14 * CGFloat(ViewRhythm.hash(index, seed: 942))
      let width = 4 + 4 * CGFloat(ViewRhythm.hash(index, seed: 943))
      ViewKit.rect(
        context, CGRect(x: x, y: top, width: width, height: 38 - top),
        city.lit(Double(index % 2) * 0.03))
      if look.isDark {
        for light in 0..<4 {
          let ly = top + 2 + CGFloat(light) * 3
          guard ly < 34, ViewRhythm.hash(index * 7 + light, seed: 944) < 0.55 else { continue }
          ViewKit.rect(
            context, CGRect(x: x + width * 0.3, y: ly, width: 0.6, height: 0.7), ViewPalette.lamp,
            0.55)
        }
      }
    }
    for index in 0..<24 {
      let x = -42 + CGFloat(index) * 8
      let size = 6 + 4 * CGFloat(ViewRhythm.hash(index, seed: 945))
      ViewKit.tree(
        context, x: x, base: 38, size: size,
        colour: Self.leafColour(index, plane: colour, look: look).mixed(with: city, by: 0.4),
        seed: 90 + index, look: look)
    }
    ViewKit.ground(context, top: 37, colour: colour.lit(-0.02))
  }

  // MARK: - Middle: trees round the pond, the bandstand

  static let middleTrees: [(x: CGFloat, size: CGFloat)] = [
    (-34, 15), (-14, 17), (2, 13), (22, 16), (42, 14), (62, 12), (88, 17), (108, 15), (128, 16),
  ]

  private func paintMiddle(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    ViewKit.ground(context, top: 39.6, colour: colour.mixed(with: ViewColour(0x7A8A3A), by: 0.15))
    for (index, tree) in Self.middleTrees.enumerated() {
      ViewKit.tree(
        context, x: tree.x, base: 40.4, size: tree.size,
        colour: Self.leafColour(index + 1, plane: colour, look: look), seed: 120 + index,
        look: look)
    }
    let pond = Self.pond
    let water = look.palette.skyMiddle.mixed(with: look.palette.horizon, by: 0.4)
      .mixed(with: colour, by: look.isDark ? 0.5 : 0.25)
    context.fill(
      Path(ellipseIn: pond.insetBy(dx: -0.8, dy: -0.4)),
      with: .color(colour.lit(look.isDark ? 0.04 : 0.1).color()))
    context.fill(
      Path(ellipseIn: pond),
      with: .linearGradient(
        Gradient(colors: [water.lit(0.08).color(), water.lit(-0.12).color()]),
        startPoint: CGPoint(x: pond.midX, y: pond.minY),
        endPoint: CGPoint(x: pond.midX, y: pond.maxY)))
    for index in 0..<6 {
      let y = pond.minY + 1 + CGFloat(index % 3) * 1.1
      let x = pond.minX + 6 + CGFloat(index) * 6
      ViewKit.rect(context, CGRect(x: x, y: y, width: 3.4, height: 0.15), water.lit(0.2), 0.6)
    }
    if look.weather == .snow {
      context.fill(
        Path(ellipseIn: pond.insetBy(dx: 3, dy: 0.8)), with: .color(ViewKit.snow(look).color(0.35)))
    }
    let stand = CGPoint(x: 76, y: 42.6)
    let roofColour = colour.mixed(with: ViewColour(0x4A6A5A), by: look.isDark ? 0.15 : 0.4)
    let white = colour.mixed(with: ViewColour(0xF0E8DC), by: look.isDark ? 0.2 : 0.5)
    ViewKit.rect(context, CGRect(x: stand.x - 7, y: stand.y - 1.6, width: 14, height: 1.6), white)
    for post in 0..<5 {
      ViewKit.rect(
        context,
        CGRect(x: stand.x - 6.2 + CGFloat(post) * 3, y: stand.y - 7.6, width: 0.45, height: 6),
        white)
    }
    ViewKit.rect(
      context, CGRect(x: stand.x - 6.4, y: stand.y - 3.6, width: 12.8, height: 0.25), white)
    var roof = Path()
    roof.move(to: CGPoint(x: stand.x - 8, y: stand.y - 7.4))
    roof.addQuadCurve(
      to: CGPoint(x: stand.x, y: stand.y - 12.4), control: CGPoint(x: stand.x - 3, y: stand.y - 8.4)
    )
    roof.addQuadCurve(
      to: CGPoint(x: stand.x + 8, y: stand.y - 7.4),
      control: CGPoint(x: stand.x + 3, y: stand.y - 8.4))
    roof.closeSubpath()
    context.fill(roof, with: .color(roofColour.color()))
    var lit = Path()
    lit.move(to: CGPoint(x: stand.x, y: stand.y - 12.4))
    lit.addQuadCurve(
      to: CGPoint(x: stand.x + 8, y: stand.y - 7.4),
      control: CGPoint(x: stand.x + 3, y: stand.y - 8.4))
    lit.addLine(to: CGPoint(x: stand.x + 2, y: stand.y - 7.4))
    lit.closeSubpath()
    context.fill(lit, with: .color(roofColour.lit(look.isDark ? 0.05 : 0.12).color()))
    ViewKit.rect(
      context, CGRect(x: stand.x - 0.15, y: stand.y - 14, width: 0.3, height: 1.8), white)
    ViewKit.circle(context, CGPoint(x: stand.x, y: stand.y - 14.1), 0.35, white)
    if look.weather == .snow {
      ViewKit.rect(
        context, CGRect(x: stand.x - 5, y: stand.y - 8.6, width: 10, height: 0.7),
        ViewKit.snow(look), 0.85)
    }
  }

  // MARK: - Street: the path

  static let benches: [CGFloat] = [28, 80]
  static let streetTrees: [(x: CGFloat, size: CGFloat)] = [(4, 22), (112, 24), (-30, 20)]
  static let leafPiles: [CGFloat] = [16, 42, 70, 96]

  private func paintStreet(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let grass = colour.mixed(with: ViewColour(0x6A7A34), by: look.isDark ? 0.1 : 0.25)
    ViewKit.ground(context, top: Self.pathTop - 1.2, colour: grass)
    let gravel = colour.mixed(with: ViewColour(0xD8C8A8), by: look.isDark ? 0.15 : 0.4)
    ViewKit.rect(
      context, CGRect(x: -45, y: Self.pathTop, width: 190, height: Self.pathBase - Self.pathTop),
      gravel)
    ViewKit.rect(
      context, CGRect(x: -45, y: Self.pathTop, width: 190, height: 0.3), gravel.lit(-0.1))
    for index in 0..<46 {
      let x = -44 + 188 * CGFloat(ViewRhythm.hash(index, seed: 951))
      let y = Self.pathTop - 1 + 4 * CGFloat(ViewRhythm.hash(index, seed: 952))
      ViewKit.circle(
        context, CGPoint(x: x, y: y), 0.35, Self.leafColour(index, plane: colour, look: look), 0.9)
    }
    for (index, x) in Self.leafPiles.enumerated() {
      for puff in 0..<6 {
        let px = x + CGFloat(puff) * 0.9 - 2.4
        let py = Self.pathTop - 0.6 - CGFloat(min(puff, 5 - puff)) * 0.45
        ViewKit.circle(
          context, CGPoint(x: px, y: py), 1.1,
          Self.leafColour(index + puff, plane: colour, look: look))
      }
    }
    for tree in Self.streetTrees {
      ViewKit.tree(
        context, x: tree.x, base: Self.pathTop - 0.4, size: tree.size,
        colour: Self.leafColour(Int(tree.size), plane: colour, look: look), seed: 160 + Int(tree.x),
        look: look)
      ViewKit.rect(
        context,
        CGRect(
          x: tree.x - tree.size * 0.06, y: Self.pathTop - 0.4 - tree.size * 0.62,
          width: tree.size * 0.12, height: tree.size * 0.62), colour.lit(-0.2))
    }
    let wood = colour.mixed(with: ViewColour(0x8A5A3A), by: look.isDark ? 0.2 : 0.45)
    for x in Self.benches {
      let seat = Self.pathTop - 2
      ViewKit.rect(context, CGRect(x: x, y: seat, width: 8, height: 0.5), wood)
      ViewKit.rect(context, CGRect(x: x, y: seat - 2.6, width: 8, height: 0.45), wood)
      ViewKit.rect(context, CGRect(x: x, y: seat - 1.6, width: 8, height: 0.45), wood.lit(-0.05))
      for leg in [x + 0.6, x + 6.9] {
        ViewKit.rect(
          context, CGRect(x: leg, y: seat - 2.6, width: 0.5, height: 4.6), colour.lit(-0.3))
      }
      if look.weather == .snow {
        ViewKit.rect(
          context, CGRect(x: x, y: seat - 0.4, width: 8, height: 0.4), ViewKit.snow(look))
      }
    }
    ViewKit.streetLampPost(
      context, x: Self.lamp.head.x + 5, top: Self.lamp.head.y - 0.6, base: Self.pathTop,
      colour: colour.lit(-0.3))
  }

  // MARK: - Near: a hedge along the bottom

  private func paintNear(_ context: GraphicsContext, colour: ViewColour, look: ViewLook) {
    let hedge = colour.mixed(with: ViewColour(0x8A4A2A), by: look.isDark ? 0.1 : 0.25)
    for index in 0..<30 {
      let x = -44 + CGFloat(index) * 6.6
      let r = 2.6 + 1.4 * CGFloat(ViewRhythm.hash(index, seed: 961))
      ViewKit.circle(context, CGPoint(x: x, y: 56.4), r, hedge.lit(index % 2 == 0 ? 0.03 : -0.02))
    }
    ViewKit.ground(context, top: 56, colour: hedge)
    if look.weather == .snow {
      for index in 0..<30 {
        let x = -44 + CGFloat(index) * 6.6
        context.fill(
          Path(ellipseIn: CGRect(x: x - 2, y: 53.4, width: 4, height: 0.9)),
          with: .color(ViewKit.snow(look).color(0.8)))
      }
    }
  }

  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far: break
    case .middle:
      ducks(context, moment: moment)
      ViewLeaves(count: 4, area: CGRect(x: -10, y: 24, width: 120, height: 18), seed: 11)
        .draw(context, moment: moment)
    case .street:
      Self.lamp.draw(context, moment: moment)
      squirrel(context, moment: moment)
      Self.walker.draw(context, moment: moment)
      Self.jogger.draw(context, moment: moment)
      ViewLeaves(count: 4, area: CGRect(x: -10, y: 18, width: 120, height: 30), seed: 12)
        .draw(context, moment: moment)
    case .near:
      ViewBranch(tint: ViewColour(0xD8843A)).draw(context, moment: moment)
      ViewLeaves(count: 3, seed: 13).draw(context, moment: moment)
    }
  }

  private static func ducksVisible(_ moment: ViewMoment) -> Bool {
    moment.look.weather != .snow
  }

  /// The lead duck gliding across the pond; the others follow in a line.
  static func duckPoint(_ pass: ViewRhythm.Pass, duck: Int) -> CGPoint {
    let p = CGFloat(pass.progress)
    let share = pass.variant < 0.5 ? p : 1 - p
    let lag: CGFloat = (pass.variant < 0.5 ? -1 : 1) * CGFloat(duck) * 2.2
    return CGPoint(
      x: pond.minX + 3 + (pond.width - 6) * share + lag,
      y: pond.midY + 0.4 + CGFloat(pass.variant) * 0.8)
  }

  private func ducks(_ context: GraphicsContext, moment: ViewMoment) {
    guard Self.ducksVisible(moment), let pass = Self.ducks.pass(at: moment.now) else { return }
    let facing: CGFloat = pass.variant < 0.5 ? 1 : -1
    let body = moment.palette.middle.lit(-0.3).mixed(
      with: ViewColour(0x8A6A4A), by: moment.look.isDark ? 0.2 : 0.4)
    let head = ViewColour(0x2E7A4A).mixed(with: body, by: moment.look.isDark ? 0.6 : 0.3)
    var pondClip = context
    pondClip.clip(to: Path(ellipseIn: Self.pond.insetBy(dx: -1, dy: -1)))
    for duck in 0..<3 {
      let point = Self.duckPoint(pass, duck: duck)
      let bob = CGFloat(sin(moment.now * 2 + Double(duck))) * 0.08
      var wake = Path()
      wake.move(to: CGPoint(x: point.x - facing * 3, y: point.y + 0.5))
      wake.addLine(to: CGPoint(x: point.x - facing * 0.6, y: point.y + 0.15))
      wake.addLine(to: CGPoint(x: point.x - facing * 3, y: point.y - 0.2))
      pondClip.stroke(
        wake, with: .color(moment.palette.skyMiddle.lit(0.3).color(0.4)), lineWidth: 0.12)
      context.fill(
        Path(
          ellipseIn: CGRect(x: point.x - 0.9, y: point.y - 0.7 + bob, width: 1.8, height: 0.8)),
        with: .color(body.color()))
      ViewKit.circle(
        context, CGPoint(x: point.x + facing * 0.7, y: point.y - 1 + bob), 0.38,
        duck == 0 ? head : body)
      ViewKit.rect(
        context,
        CGRect(x: point.x + facing * 1.0 - 0.2, y: point.y - 1.05 + bob, width: 0.4, height: 0.18),
        ViewColour(0xE8A030).mixed(with: body, by: 0.3))
    }
  }

  static func squirrelPoint(_ pass: ViewRhythm.Pass) -> (CGPoint, climbing: Bool) {
    let tree = climbTree
    let p = CGFloat(pass.progress)
    let ground = tree.base - 3.4
    switch p {
    case ..<0.2: return (CGPoint(x: tree.x + 14 - 13 * p / 0.2, y: ground), false)
    case ..<0.45:
      return (CGPoint(x: tree.x + 0.9, y: ground - (ground - tree.top) * (p - 0.2) / 0.25), true)
    case ..<0.75: return (CGPoint(x: tree.x + 0.9, y: tree.top), true)
    default:
      return (CGPoint(x: tree.x + 0.9, y: tree.top + (ground - tree.top) * (p - 0.75) / 0.25), true)
    }
  }

  private func squirrel(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.hour != .night, moment.look.weather != .rain,
      let pass = Self.squirrel.pass(at: moment.now)
    else { return }
    let (point, climbing) = Self.squirrelPoint(pass)
    let fur = ViewColour(0xB8602A).mixed(
      with: moment.palette.street, by: moment.look.isDark ? 0.5 : 0.25)
    var body = context
    body.translateBy(x: point.x, y: point.y)
    if climbing { body.rotate(by: .degrees(-90)) }
    let flick = CGFloat(sin(moment.now * 7)) * 0.3
    body.fill(
      Path(ellipseIn: CGRect(x: -0.9, y: -0.5, width: 1.8, height: 0.9)), with: .color(fur.color()))
    ViewKit.circle(body, CGPoint(x: -1, y: -0.5), 0.42, fur)
    var tail = Path()
    tail.move(to: CGPoint(x: 0.8, y: -0.2))
    tail.addQuadCurve(to: CGPoint(x: 0.9 + flick, y: -2.2), control: CGPoint(x: 2.2, y: -0.8))
    body.stroke(
      tail, with: .color(fur.lit(0.05).color()), style: StrokeStyle(lineWidth: 0.7, lineCap: .round)
    )
  }

  func headlight(at now: Double) -> ViewHeadlight? { nil }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if moment.look.hour != .night, moment.look.weather != .rain,
      let pass = Self.squirrel.pass(at: moment.now)
    {
      return ViewInterest(
        point: Self.squirrelPoint(pass).0, plane: .street, paw: false, id: pass.index)
    }
    if Self.ducksVisible(moment), let pass = Self.ducks.pass(at: moment.now) {
      return ViewInterest(
        point: Self.duckPoint(pass, duck: 0), plane: .middle, paw: false, id: pass.index)
    }
    return Self.jogger.interest(at: moment.now) ?? Self.walker.interest(at: moment.now)
  }
}
