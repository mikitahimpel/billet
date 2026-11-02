import CoreGraphics
import Foundation
import Pet
import PetScene
import simd

/// What a room keeps about the hands on its cat: the play machine, the stroke in progress and
/// how far the cat leans into it. Rooms own one and step ``lean`` each frame.
@MainActor
final class CatHands {
  var play = CatPlay(seed: UInt64.random(in: 1...UInt64.max))
  /// The body's roll towards the hand, in radians, and where it is easing to.
  private(set) var lean: Float = 0
  var leanGoal: Float = 0
  /// Until when the cat lies on its back, so a stroke on its middle is a belly rub.
  var onBackUntil = -Double.infinity
  private var lastPoint: SIMD2<Double>?
  private var lastStroke: (zone: PetZone, direction: StrokeDirection, at: Double)?
  /// The reaction last played and when, so a stroke that goes on does not restart its clip.
  private var lastShown: (reaction: CatPlayReaction, at: Double)?

  static let leanAngle: Float = 0.13
  /// How often an unchanged stroke is told to the machine again.
  static let strokeRepeat = 0.8
  /// How long a reaction plays before the same one starts again.
  static let reshow = 2.4

  func isOnBack(at now: Double) -> Bool { now < onBackUntil }

  func beginStroke(at point: CGPoint) {
    lastPoint = SIMD2(Double(point.x), Double(point.y))
    lastStroke = nil
  }

  func endStroke() {
    lastPoint = nil
    lastStroke = nil
    leanGoal = 0
  }

  /// The machine's answer to the finger now at `point` on `body`, when the stroke has changed
  /// enough to be worth telling it.
  func stroke(to point: CGPoint, on body: CatBodyOnScreen, at now: Double) -> CatPlayResponse? {
    let here = SIMD2(Double(point.x), Double(point.y))
    let delta = here - (lastPoint ?? here)
    guard simd_length(delta) >= 6 || lastStroke == nil else { return nil }
    lastPoint = here
    let zone = body.zone(at: here)
    let direction = body.direction(of: delta)
    // Towards the side of the body the hand is on, as the screen shows it.
    let axis = body.tail - body.head
    let side = axis.x * (here.y - body.head.y) - axis.y * (here.x - body.head.x)
    leanGoal = (side > 0 ? 1 : -1) * Self.leanAngle
    if let lastStroke, lastStroke.zone == zone, lastStroke.direction == direction,
      now - lastStroke.at < Self.strokeRepeat
    {
      return nil
    }
    lastStroke = (zone, direction, now)
    return play.handle(.stroke(zone, direction), at: now)
  }

  /// Whether `reaction` should start its clip now, rather than let the one playing go on.
  func shouldShow(_ reaction: CatPlayReaction, at now: Double) -> Bool {
    if let lastShown, lastShown.reaction == reaction, now - lastShown.at < Self.reshow {
      return false
    }
    lastShown = (reaction, now)
    return true
  }

  /// Eases the lean towards its goal; a flick leans away harder for a moment.
  func stepLean(_ delta: Float, reduceMotion: Bool) {
    let goal = reduceMotion ? 0 : leanGoal
    lean += (goal - lean) * (1 - exp(-6 * delta))
  }
}

extension CatBodyOnScreen {
  /// The cat standing or sitting at `base` facing `heading`, `length` long, as `project` draws it.
  @MainActor
  static func of(
    base: SIMD3<Float>, heading: Float, length: Float, isOnBack: Bool,
    project: (SIMD3<Float>) -> CGPoint?
  ) -> CatBodyOnScreen? {
    let forward = SIMD3<Float>(-sin(heading), 0, -cos(heading))
    let up = SIMD3<Float>(0, 1, 0)
    guard
      let head = project(base + forward * length * 0.36 + up * length * 0.42),
      let tail = project(base - forward * length * 0.3 + up * length * 0.28),
      let middle = project(base + up * length * 0.3),
      let top = project(base + up * length * 0.62)
    else { return nil }
    let girth = max(hypot(top.x - middle.x, top.y - middle.y), 30)
    return CatBodyOnScreen(
      head: SIMD2(Double(head.x), Double(head.y)), tail: SIMD2(Double(tail.x), Double(tail.y)),
      girth: Double(girth), isOnBack: isOnBack)
  }
}

/// A room whose cat answers hands through ``CatHands``.
@MainActor
protocol CatPlayStage: AnyObject {
  var hands: CatHands { get }
  var purr: CatPurr { get }
  var behaviour: CatBehaviour { get set }
  var clock: Double { get }
  /// Plays the reactions to toys, food, lifting, calling and the partner.
  func showPlay(_ response: CatPlayResponse)
}

extension CatPlayStage {
  /// Plays the machine's answer with the cat's own clips, and says what to report.
  func show(_ response: CatPlayResponse) -> [PetSceneEvent] {
    if let haptic = response.haptic { purr.feel(haptic) }
    if hands.shouldShow(response.reaction, at: clock) {
      switch response.reaction {
      case .lean(let eyesClosed):
        if hands.isOnBack(at: clock) { break }
        if eyesClosed {
          behaviour.perform(.slowBlink, for: CatHands.reshow, at: clock)
        } else {
          behaviour.react(.pet, at: clock)
        }
      case .flick:
        hands.leanGoal = -hands.leanGoal * 1.4
        behaviour.perform(.tailFlick, for: 1.4, at: clock)
      case .grab:
        hands.onBackUntil = clock + 2.5
        behaviour.perform(.grab, at: clock)
      default:
        showPlay(response)
      }
    }
    switch response.need {
    case .play: return [.played]
    case .feed: return [.fed]
    case nil: return []
    }
  }

}
