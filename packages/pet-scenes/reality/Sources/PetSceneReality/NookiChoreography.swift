import Foundation
import Pet
import PetScene

/// Where the diorama should be at a moment of the current step.
struct NookiFrame: Equatable {
  /// How far Mochi has risen, from curled up at 0 to awake at 1.
  var wake: Float = 0
  var eyesOpen = false
  /// How far the note has come towards Mochi, from out of sight at 0 to carried at 1.
  var note: Float = 0
  /// How far the carried note has gone to the wire, from 0 to hanging at 1.
  var pinned: Float = 0
  /// Height of the happy hop, from 0 to 1.
  var hop: Float = 0
  /// Position along the walk, from the bed at 0 to the note wall at 1.
  var walk: Float = 0
  /// Height of the current step of the walk, from 0 to 1.
  var stepHeight: Float = 0
  /// Squash and stretch, from -1 squashed on landing to 1 stretched in the air.
  var stretch: Float = 0
  /// Which way Mochi faces, as a yaw in radians.
  var heading: Float = NookiChoreography.restHeading
  /// How much of the window's light the room shows, and how far Mochi has turned to it: 0 or 1.
  /// The diorama eases towards it, so a change does not jump.
  var light: Float = 0
}

/// The animation of each step, as a pure function of time.
///
/// The body's own movement comes from Mochi's clips; this says where it goes and what it is doing.
/// The note rides above Mochi to the wall. Reduce Motion keeps Mochi in the bed and lets the note
/// appear on the wire.
enum NookiChoreography {
  static let pacing = PetScenePacing(delivery: .seconds(9), settling: .seconds(2.5))

  static let restHeading: Float = 3.8
  private static let awakeHeading: Float = 4.3
  private static let towardsWall: Float = 2 * .pi
  private static let towardsBed: Float = .pi

  private static let hops = 5.0
  private static let walkOut = 1.2...3.4
  private static let walkBack = 5.0...7.2
  private static let noteComes = 0.8...1.6
  private static let notePins = 3.4...4.0
  private static let happyHop = 4.0...4.8
  private static let wakeLength = 1.0
  private static let eyesOpenAt = 0.3
  private static let settleLength = 2.0
  private static let eyesCloseAt = 1.5

  private static let headings: [(time: Double, value: Float)] = [
    (0, restHeading), (1, awakeHeading), (1.3, towardsWall), (4.0, towardsWall),
    (4.4, awakeHeading), (5.0, awakeHeading), (5.3, towardsBed), (7.2, towardsBed),
    (7.8, awakeHeading),
  ]

  static func frame(_ world: PetWorld, elapsed: Double, reduceMotion: Bool = false) -> NookiFrame {
    var frame = stepFrame(world, elapsed: elapsed, reduceMotion: reduceMotion)
    frame.light = world.partnerHere ? 1 : 0
    return frame
  }

  private static func stepFrame(
    _ world: PetWorld, elapsed: Double, reduceMotion: Bool
  ) -> NookiFrame {
    switch world.activity {
    case .sleeping:
      let hung: Float = world.delivery > 0 ? 1 : 0
      return NookiFrame(note: hung, pinned: hung)
    case .delivering:
      return reduceMotion ? stillDelivery(elapsed) : delivery(elapsed)
    case .settling:
      return NookiFrame(
        wake: 1 - ease(elapsed / settleLength),
        eyesOpen: elapsed < eyesCloseAt,
        note: 1,
        pinned: 1,
        heading: awakeHeading + (restHeading - awakeHeading) * ease(elapsed / settleLength)
      )
    }
  }

  private static func delivery(_ elapsed: Double) -> NookiFrame {
    var frame = NookiFrame(
      wake: ease(elapsed / wakeLength),
      eyesOpen: elapsed >= eyesOpenAt,
      note: ease(fraction(elapsed, in: noteComes)),
      pinned: ease(fraction(elapsed, in: notePins)),
      heading: track(headings, at: elapsed)
    )
    let hop = fraction(elapsed, in: happyHop)
    frame.hop = hop > 0 && hop < 1 ? arch(hop) : 0
    if walkOut.contains(elapsed) {
      frame.walk = Float(fraction(elapsed, in: walkOut))
      applyStride(fraction(elapsed, in: walkOut), to: &frame)
    } else if walkBack.contains(elapsed) {
      frame.walk = 1 - Float(fraction(elapsed, in: walkBack))
      applyStride(fraction(elapsed, in: walkBack), to: &frame)
    } else if elapsed > walkOut.upperBound, elapsed < walkBack.lowerBound {
      frame.walk = 1
    }
    return frame
  }

  private static func stillDelivery(_ elapsed: Double) -> NookiFrame {
    let arrived: Float = elapsed >= noteComes.upperBound ? 1 : 0
    return NookiFrame(
      wake: elapsed >= eyesOpenAt ? 1 : 0,
      eyesOpen: elapsed >= eyesOpenAt,
      note: arrived,
      pinned: arrived,
      heading: awakeHeading
    )
  }

  private static func applyStride(_ progress: Double, to frame: inout NookiFrame) {
    let phase = (progress * hops).truncatingRemainder(dividingBy: 1)
    frame.stepHeight = arch(phase)
    frame.stretch = Float(-cos(2 * .pi * phase))
  }

  private static func fraction(_ elapsed: Double, in span: ClosedRange<Double>) -> Double {
    min(max((elapsed - span.lowerBound) / (span.upperBound - span.lowerBound), 0), 1)
  }

  private static func track(_ keys: [(time: Double, value: Float)], at time: Double) -> Float {
    guard let first = keys.first, let last = keys.last else { return restHeading }
    guard time > first.time else { return first.value }
    for (from, to) in zip(keys, keys.dropFirst()) where time < to.time {
      let progress = (time - from.time) / (to.time - from.time)
      return from.value + (to.value - from.value) * ease(progress)
    }
    return last.value
  }

  private static func ease(_ value: Double) -> Float {
    let t = min(max(value, 0), 1)
    return Float(t * t * (3 - 2 * t))
  }

  /// Rises from 0 to 1 and back as `value` goes from 0 to 1.
  static func arch(_ value: Double) -> Float {
    let t = 2 * value - 1
    return Float(1 - t * t)
  }
}
