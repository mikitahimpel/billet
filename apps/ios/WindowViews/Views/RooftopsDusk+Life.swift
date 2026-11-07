import CoreGraphics
import Foundation
import Pet
import SwiftUI

extension RooftopsDusk {
  // MARK: - Life

  func life(_ plane: ViewPlane, _ context: GraphicsContext, moment: ViewMoment) {
    switch plane {
    case .far, .near: break
    case .middle:
      ViewWindows.draw(Self.middleWindows, context, moment: moment)
      smoke(context, moment: moment)
      Self.roofCat.draw(context, moment: moment)
      swifts(context, moment: moment)
    case .street:
      ViewWindows.draw(Self.streetWindows, context, moment: moment)
      watering(context, moment: moment)
      balconies(context, moment: moment)
    }
  }

  private func smoke(_ context: GraphicsContext, moment: ViewMoment) {
    let colour = moment.palette.skyMiddle.lit(moment.look.isDark ? 0.15 : 0.35)
    let top = Self.chimney
    let wind = moment.look.weather == .rain ? 2.0 : 1
    for puff in 0..<6 {
      let p = (moment.now * 0.11 + Double(puff) / 6).truncatingRemainder(dividingBy: 1)
      let rise = CGFloat(p) * 15
      let drift =
        CGFloat(p * p * wind) * 9 + CGFloat(sin(moment.now * 0.5 + Double(puff))) * 0.8
      ViewKit.circle(
        context, CGPoint(x: top.x + drift, y: top.y - rise), 0.7 + CGFloat(p) * 2.2, colour,
        0.3 * (1 - p))
    }
  }

  private static func swiftsVisible(_ moment: ViewMoment) -> Bool {
    moment.look.hour != .night && (moment.look.weather == .clear || moment.look.weather == .fog)
  }

  /// A swift of the screaming party: each bird circles its own loop round a moving centre.
  static func swiftPoint(_ pass: ViewRhythm.Pass, bird: Int, now: Double) -> CGPoint {
    let p = CGFloat(pass.progress)
    let leftToRight = pass.variant < 0.5
    let centreX = leftToRight ? -30 + 160 * p : 130 - 160 * p
    let centreY = 6 + 8 * CGFloat(pass.variant)
    let speed = 1.1 + 0.4 * ViewRhythm.hash(bird, seed: 851)
    let angle = now * speed + Double(bird) * 1.9
    let radius = 5 + 5 * CGFloat(ViewRhythm.hash(bird, seed: 852))
    return CGPoint(
      x: centreX + CGFloat(cos(angle)) * radius * 1.5, y: centreY + CGFloat(sin(angle)) * radius)
  }

  private func swifts(_ context: GraphicsContext, moment: ViewMoment) {
    guard Self.swiftsVisible(moment), let pass = Self.swifts.pass(at: moment.now) else { return }
    let colour = moment.palette.middle.lit(-0.35)
    for bird in 0..<7 {
      let point = Self.swiftPoint(pass, bird: bird, now: moment.now)
      let flap = CGFloat(sin(moment.now * 18 + Double(bird) * 2.1)) * 0.5
      var wings = Path()
      wings.move(to: CGPoint(x: point.x - 1.1, y: point.y - 0.3 - flap))
      wings.addQuadCurve(
        to: CGPoint(x: point.x, y: point.y), control: CGPoint(x: point.x - 0.5, y: point.y - 0.1))
      wings.addQuadCurve(
        to: CGPoint(x: point.x + 1.1, y: point.y - 0.3 - flap),
        control: CGPoint(x: point.x + 0.5, y: point.y - 0.1))
      context.stroke(wings, with: .color(colour.color()), lineWidth: 0.3)
    }
  }

  /// The neighbour across stepping out to water the geraniums: out, tip the can, back in.
  private func watering(_ context: GraphicsContext, moment: ViewMoment) {
    guard moment.look.hour != .night, moment.look.weather != .rain,
      let pass = Self.waterer.pass(at: moment.now)
    else { return }
    let window = Self.watererWindow
    let p = pass.progress
    // Steps forward for the first tenth, waters, steps back for the last tenth.
    let out = CGFloat(min(min(p / 0.1, (1 - p) / 0.1), 1))
    let feet = CGPoint(x: window.midX, y: window.maxY + 0.6)
    var person = context
    person.opacity = Double(out)
    ViewWalker.figure(
      person, at: feet, height: 5.8, facing: -1, kind: .walker, coat: 0xE8C8A0, plane: .street,
      moment: moment, walking: false)
    guard out > 0.9 else { return }
    // The can, held out over the box, and its drops.
    let can = CGPoint(x: feet.x - 2.6, y: feet.y - 3.6)
    let tin = ViewColour(0x6A9AA0).mixed(with: moment.palette.street, by: 0.35)
    ViewKit.rect(person, CGRect(x: can.x - 0.7, y: can.y - 0.5, width: 1.4, height: 1.1), tin)
    var spout = Path()
    spout.move(to: CGPoint(x: can.x - 0.7, y: can.y))
    spout.addLine(to: CGPoint(x: can.x - 1.9, y: can.y + 0.3))
    person.stroke(spout, with: .color(tin.color()), lineWidth: 0.2)
    for drop in 0..<4 {
      let fall = (moment.now * 2.2 + Double(drop) / 4).truncatingRemainder(dividingBy: 1)
      ViewKit.circle(
        person, CGPoint(x: can.x - 2, y: can.y + 0.5 + CGFloat(fall) * 2.4), 0.12,
        ViewColour(0xCFE4FF), 0.8 * (1 - fall))
    }
  }

  func headlight(at now: Double) -> ViewHeadlight? { nil }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    if Self.swiftsVisible(moment), let pass = Self.swifts.pass(at: moment.now) {
      let lead = Self.swiftPoint(pass, bird: 0, now: moment.now)
      if lead.x > 0, lead.x < 100 {
        return ViewInterest(point: lead, plane: .middle, paw: false, id: pass.index)
      }
    }
    if let cat = Self.roofCat.interest(at: moment.now) { return cat }
    if moment.look.hour != .night, moment.look.weather != .rain,
      let pass = Self.waterer.pass(at: moment.now)
    {
      let window = Self.watererWindow
      return ViewInterest(
        point: CGPoint(x: window.midX - 2.6, y: window.maxY - 3), plane: .street, paw: false,
        id: pass.index)
    }
    return nil
  }
}
