import Pet
import PetScene

/// Where the diorama should be at a moment of the current step.
struct NookiFrame: Equatable {
  /// How far Mochi has risen, from curled up at 0 to awake at 1.
  var wake: Float = 0
  var eyesOpen = false
  /// How far the note has travelled, from out of sight at 0 to hanging on the wire at 1.
  var note: Float = 0
  /// Height of the proud hop, from 0 to 1.
  var hop: Float = 0
  /// How much of the window's light the room shows, and how far Mochi has turned to it: 0 or 1.
  /// The diorama eases towards it, so a change does not jump.
  var light: Float = 0
}

/// The animation of each step, as a pure function of time.
///
/// `Cat.usdz` has no skeleton or clips, so Mochi cannot walk. Waking is a whole-body rise plus a
/// swap of the closed eye meshes for open ones, and the note travels to the wire on its own.
enum NookiChoreography {
  static let pacing = PetScenePacing(delivery: .seconds(7), settling: .seconds(2.5))

  private static let wakeLength = 1.0
  private static let noteStart = 1.2
  private static let noteLength = 2.5
  private static let hopStart = 4.2
  private static let hopLength = 1.2
  private static let eyesOpenAt = 0.3
  private static let settleLength = 2.0
  private static let eyesCloseAt = 1.5

  static func frame(_ world: PetWorld, elapsed: Double) -> NookiFrame {
    var frame = stepFrame(world, elapsed: elapsed)
    frame.light = world.partnerHere ? 1 : 0
    return frame
  }

  private static func stepFrame(_ world: PetWorld, elapsed: Double) -> NookiFrame {
    switch world.activity {
    case .sleeping:
      return NookiFrame(note: world.delivery > 0 ? 1 : 0)
    case .delivering:
      let hop = (elapsed - hopStart) / hopLength
      return NookiFrame(
        wake: ease(elapsed / wakeLength),
        eyesOpen: elapsed >= eyesOpenAt,
        note: ease((elapsed - noteStart) / noteLength),
        hop: (0...1).contains(hop) ? arch(hop) : 0
      )
    case .settling:
      return NookiFrame(
        wake: 1 - ease(elapsed / settleLength),
        eyesOpen: elapsed < eyesCloseAt,
        note: 1
      )
    }
  }

  private static func ease(_ value: Double) -> Float {
    let t = min(max(value, 0), 1)
    return Float(t * t * (3 - 2 * t))
  }

  /// Rises from 0 to 1 and back as `value` goes from 0 to 1.
  private static func arch(_ value: Double) -> Float {
    let t = 2 * value - 1
    return Float(1 - t * t)
  }
}
