import CoreGraphics
import Foundation
import Pet
import SwiftUI

struct ViewShootingStar: Sendable {
  var rhythm: ViewRhythm
  /// Where streaks may start, in stage units.
  var area = CGRect(x: 0, y: -8, width: 100, height: 16)

  func head(_ pass: ViewRhythm.Pass) -> (point: CGPoint, direction: CGVector) {
    let start = CGPoint(
      x: area.minX + area.width * CGFloat(ViewRhythm.hash(Int(pass.index % 10_000), seed: 881)),
      y: area.minY + area.height * CGFloat(ViewRhythm.hash(Int(pass.index % 10_000), seed: 882)))
    let leftward = pass.variant < 0.5
    let direction = CGVector(dx: leftward ? -1 : 1, dy: 0.42)
    let travel = 26 * CGFloat(pass.progress)
    return (
      CGPoint(x: start.x + direction.dx * travel, y: start.y + direction.dy * travel), direction
    )
  }

  func isVisible(_ moment: ViewMoment) -> Bool {
    moment.look.isDark && moment.look.weather == .clear
  }

  func draw(_ context: GraphicsContext, moment: ViewMoment) {
    guard isVisible(moment), let pass = rhythm.pass(at: moment.now) else { return }
    let (point, direction) = head(pass)
    let p = pass.progress
    let level = min(p / 0.15, 1) * min((1 - p) / 0.4, 1)
    let length: CGFloat = 9 * CGFloat(min(p / 0.3, 1))
    let tail = CGPoint(x: point.x - direction.dx * length, y: point.y - direction.dy * length)
    var streak = Path()
    streak.move(to: tail)
    streak.addLine(to: point)
    context.stroke(
      streak,
      with: .linearGradient(
        Gradient(colors: [ViewColour(0xEEF2FF).color(0), ViewColour(0xFFFFFF).color(level)]),
        startPoint: tail, endPoint: point),
      style: StrokeStyle(lineWidth: 0.35, lineCap: .round))
    ViewKit.glow(context, point, 1.6, ViewColour(0xE8F0FF), 0.6 * level)
  }

  func interest(at moment: ViewMoment) -> ViewInterest? {
    guard isVisible(moment), let pass = rhythm.pass(at: moment.now) else { return nil }
    let point = head(pass).point
    guard point.x > 0, point.x < 100 else { return nil }
    return ViewInterest(point: point, plane: .far, paw: false, id: pass.index)
  }
}
