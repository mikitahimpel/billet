import Foundation
import Pet

/// A walk round every surface the cat can be on, in place of the brain's steps, for recording
/// how it stands and moves on each: switched on by the launch argument `-ground.tour YES`, off
/// otherwise. Down to the cat bed to sleep, onto the rug to sit, back up to the window seat to
/// loaf, onto the cardigan, and round again.
enum GenzCatTour {
  static let isOn = UserDefaults.standard.bool(forKey: "ground.tour")

  private static let legs: [(CatActivityStep, CatAction, CatTarget, Double)] = [
    (.findNapSpot, .sleep, .affordance(.bed), 14),
    (.inspectFurniture, .sit, .affordance(.rug), 9),
    (.loaf, .loaf, .home, 9),
    (.knead, .sit, .affordance(.soft), 8),
    (.lookAround, .sit, .affordance(.window), 7),
  ]

  /// The tour's step at `clock` seconds into the room.
  static func frame(at clock: Double) -> CatBrainFrame {
    let lap = legs.map(\.3).reduce(0, +)
    var into = clock.truncatingRemainder(dividingBy: lap)
    let laps = (clock / lap).rounded(.down)
    var start = laps * lap
    for (step, action, target, length) in legs {
      if into < length {
        return CatBrainFrame(
          stack: CatBrainStack(vitality: .awake, step: step), action: action, target: target,
          gaze: .ahead, pace: 0, stepStart: start, stepEnd: start + length)
      }
      into -= length
      start += length
    }
    let first = legs[0]
    return CatBrainFrame(
      stack: CatBrainStack(vitality: .awake, step: first.0), action: first.1, target: first.2,
      gaze: .ahead, pace: 0, stepStart: start, stepEnd: start + first.3)
  }
}
