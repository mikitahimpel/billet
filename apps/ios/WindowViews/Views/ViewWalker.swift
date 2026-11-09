import CoreGraphics
import Foundation
import Pet
import SwiftUI

struct ViewWalker: Sendable {
  enum Kind: Sendable {
    case walker
    case backpack
    case phone
    case skater
    case dog
  }

  var rhythm: ViewRhythm
  /// Where their feet are at the start of a left-to-right pass.
  var from: CGPoint
  /// Where their feet are at its end.
  var to: CGPoint
  var height: CGFloat = 7
  var plane = ViewPlane.street
  var kinds: [Kind] = [.walker]
  /// Coat colours, picked per pass and mixed into the plane's shadow.
  var coats: [UInt32] = [0x3A5A8A, 0x8A3A4A, 0x4A6A3A, 0xC8A050]

  func kind(_ pass: ViewRhythm.Pass) -> Kind {
    kinds[Int(pass.variant * 97) % max(kinds.count, 1)]
  }

  func point(_ pass: ViewRhythm.Pass) -> CGPoint {
    let p = CGFloat(pass.progress)
    let share = pass.variant < 0.5 ? p : 1 - p
    return CGPoint(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share)
  }

  func interest(at now: Double) -> ViewInterest? {
    guard let pass = rhythm.pass(at: now) else { return nil }
    let point = point(pass)
    guard point.x > -5, point.x < 105 else { return nil }
    return ViewInterest(
      point: CGPoint(x: point.x, y: point.y - height * 0.6), plane: plane, paw: false,
      id: pass.index)
  }

  func draw(_ context: GraphicsContext, moment: ViewMoment) {
    guard let pass = rhythm.pass(at: moment.now) else { return }
    Self.figure(
      context, at: point(pass), height: height, facing: pass.variant < 0.5 ? 1 : -1,
      kind: kind(pass), coat: coats[Int(pass.variant * 53) % coats.count], plane: plane,
      moment: moment, walking: true)
  }

  static func figure(
    _ context: GraphicsContext, at point: CGPoint, height: CGFloat, facing: CGFloat, kind: Kind,
    coat coatColour: UInt32, plane: ViewPlane, moment: ViewMoment, walking: Bool
  ) {
    let shadow = moment.palette.colour(plane).lit(-0.35)
    let coat = shadow.mixed(with: ViewColour(coatColour), by: moment.look.isDark ? 0.25 : 0.5)
    let unit = height / 7
    var person = context
    person.translateBy(x: point.x, y: point.y)
    person.scaleBy(x: unit * facing, y: unit)
    let stride = walking && kind != .skater ? sin(moment.now * 6.5) * 0.5 : 0
    switch kind {
    case .skater:
      person.rotate(by: .degrees(6))
      person.fill(
        Path(roundedRect: CGRect(x: -1.8, y: -0.6, width: 3.6, height: 0.35), cornerRadius: 0.17),
        with: .color(shadow.color()))
      for x in [-1.2, 1.2] as [CGFloat] {
        person.fill(
          Path(ellipseIn: CGRect(x: x - 0.3, y: -0.3, width: 0.6, height: 0.6)),
          with: .color(shadow.lit(0.15).color()))
      }
      for x in [-0.9, 0.5] as [CGFloat] {
        person.fill(
          Path(CGRect(x: x, y: -2.7, width: 0.45, height: 2.1)), with: .color(shadow.color()))
      }
      person.translateBy(x: 0, y: -0.6)
    case .walker, .backpack, .phone, .dog:
      for (x, phase) in [(-0.6, stride), (0.2, -stride)] as [(CGFloat, CGFloat)] {
        person.fill(
          Path(CGRect(x: x + phase * 0.6, y: -2.1, width: 0.45, height: 2.1)),
          with: .color(shadow.color()))
      }
    }
    person.fill(
      Path(roundedRect: CGRect(x: -0.9, y: -5.6, width: 1.8, height: 3.6), cornerRadius: 0.7),
      with: .color(coat.color()))
    person.fill(
      Path(ellipseIn: CGRect(x: -0.6, y: -6.8, width: 1.2, height: 1.3)),
      with: .color(shadow.color()))
    switch kind {
    case .backpack:
      person.fill(
        Path(roundedRect: CGRect(x: -1.6, y: -5.3, width: 0.9, height: 2.4), cornerRadius: 0.3),
        with: .color(coat.lit(0.15).mixed(with: ViewColour(0xE5503A), by: 0.3).color()))
    case .phone:
      let screen = ViewColour(0xCFE4FF)
      person.fill(
        Path(CGRect(x: 0.6, y: -5.2, width: 0.35, height: 0.6)),
        with: .color(screen.color(moment.look.isDark ? 1 : 0.5)))
      if moment.look.isDark {
        ViewKit.glow(person, CGPoint(x: 0.6, y: -5.6), 1.6, screen, 0.5)
      }
    case .dog:
      let trot = walking ? CGFloat(sin(moment.now * 13)) * 0.3 : 0
      person.fill(
        Path(ellipseIn: CGRect(x: 2.6, y: -1.9, width: 2.6, height: 1.2)),
        with: .color(shadow.color()))
      person.fill(
        Path(ellipseIn: CGRect(x: 4.6, y: -2.6, width: 1.2, height: 1.1)),
        with: .color(shadow.color()))
      for (x, phase) in [(2.9, trot), (4.6, -trot)] as [(CGFloat, CGFloat)] {
        person.fill(
          Path(CGRect(x: x + phase, y: -1, width: 0.3, height: 1)), with: .color(shadow.color()))
      }
      person.fill(
        Path(ellipseIn: CGRect(x: 2.2, y: -2.3, width: 0.9, height: 0.4)),
        with: .color(shadow.color()))
      var lead = Path()
      lead.move(to: CGPoint(x: 0.8, y: -3.8))
      lead.addQuadCurve(to: CGPoint(x: 4.8, y: -2.2), control: CGPoint(x: 3, y: -2))
      person.stroke(lead, with: .color(shadow.lit(0.2).color()), lineWidth: 0.12)
    case .walker, .skater: break
    }
  }
}
