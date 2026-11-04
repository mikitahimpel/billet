import Foundation

/// The reflex region: blinks, ear twitches, tail flicks and breath, always running beside the
/// rest of the brain. Each is a pure function of the time and the seed, worked out on a few-second
/// grid with no state, so a frame costs a handful of multiplications and nothing is allocated.
public struct CatReflexes: Hashable, Sendable {
  public var blink: Bool
  public var earTwitch: Bool
  public var tailFlick: Bool
  /// Where the breath is, from 0 to 1 and round again.
  public var breath: Double

  /// Seconds per slot; each slot holds at most one of each reflex.
  static let slot = 4.0
  static let blinkLength = 0.18
  static let twitchLength = 0.35
  static let flickLength = 0.9

  public static func at(_ t: Double, seed: UInt64, vitality: CatVitality) -> CatReflexes {
    let index = (t / slot).rounded(.down)
    let into = t - index * slot
    let start = index * slot
    func fires(_ salt: UInt64, chance: Double, length: Double) -> Bool {
      guard BrainDice.roll(seed, start, salt) < chance else { return false }
      let at = BrainDice.roll(seed, start, salt &+ 1) * (slot - length)
      return into >= at && into < at + length
    }
    let awake = vitality != .asleep
    // Asleep it breathes slower and deeper; blinks stop and only the ears flick now and then.
    let rate = awake ? 0.38 : 0.22
    return CatReflexes(
      blink: awake && fires(21, chance: vitality == .drowsy ? 0.9 : 0.7, length: blinkLength),
      earTwitch: fires(23, chance: awake ? 0.2 : 0.12, length: twitchLength),
      tailFlick: awake && fires(25, chance: 0.18, length: flickLength),
      breath: (t * rate).truncatingRemainder(dividingBy: 1))
  }

  /// The one-shot a model plays for a reflex where it has no layer for it: a blink or a flick in
  /// the middle of a calm step. Nil leaves the step's own clip playing.
  public func oneShot(during step: CatActivityStep) -> CatAction? {
    guard Self.calm.contains(step) else { return nil }
    if tailFlick { return .tailFlick }
    if blink { return .blink }
    return nil
  }

  /// Steps quiet enough for a reflex clip to cut in without being noticed as a cut.
  public static let calm: Set<CatActivityStep> = [
    .sit, .loaf, .watchWindow, .waitByDoor, .waitByBowl, .sitInCardigan, .sitOnDesk,
  ]
}
