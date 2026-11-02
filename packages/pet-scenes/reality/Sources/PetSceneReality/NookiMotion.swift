import Foundation

/// Reactions to touch and the room's idle loops, as pure functions of time.
///
/// Reduce Motion stills everything here except waking, which is a change of state rather than
/// movement.
enum NookiMotion {
  /// How long an object keeps wobbling.
  static let wobbleLength = 1.5
  /// How long Mochi stays up after a pet.
  static let petLength = 2.0
  /// How long Mochi keeps looking at something tapped.
  static let lookLength = 1.6

  /// Tilt of a tapped object, in radians, dying away.
  static func wobble(_ elapsed: Double, reduceMotion: Bool) -> Float {
    guard !reduceMotion, (0..<wobbleLength).contains(elapsed) else { return 0 }
    return Float(0.05 * exp(-3 * elapsed) * sin(14 * elapsed))
  }

  /// Mochi's reaction to a pet.
  static func pet(_ elapsed: Double, reduceMotion: Bool) -> NookiFrame {
    guard (0..<petLength).contains(elapsed) else { return NookiFrame() }
    let eyesOpen = elapsed < petLength - 0.3
    if reduceMotion { return NookiFrame(eyesOpen: eyesOpen) }
    let rise = min(elapsed / 0.3, (petLength - elapsed) / 0.5)
    let hop = (elapsed - 0.3) / 0.5
    return NookiFrame(
      wake: Float(min(max(rise, 0), 1)),
      eyesOpen: eyesOpen,
      hop: (0...1).contains(hop) ? NookiChoreography.arch(hop) * 0.6 : 0
    )
  }

  /// The lamp's brightness, close to 1.
  static func flicker(_ time: Double, reduceMotion: Bool) -> Float {
    guard !reduceMotion else { return 1 }
    return Float(1 + 0.04 * sin(time * 9.1) + 0.025 * sin(time * 23.7 + 1))
  }

  /// The plant's lean, in radians.
  static func sway(_ time: Double, reduceMotion: Bool) -> Float {
    reduceMotion ? 0 : Float(0.016 * sin(time * 0.9))
  }
}

extension NookiFrame {
  /// The stronger of two frames, so a reaction shows without disturbing the delivery underneath.
  func combined(with other: NookiFrame) -> NookiFrame {
    var combined = self
    combined.wake = max(wake, other.wake)
    combined.eyesOpen = eyesOpen || other.eyesOpen
    combined.hop = max(hop, other.hop)
    return combined
  }
}
