import Foundation

/// Short reactions to touch, as pure functions of the time since the touch.
enum NookiMotion {
  /// How long an object keeps wobbling.
  static let wobbleLength = 1.5
  /// How long Mochi stays up after a pet.
  static let petLength = 2.0

  /// Tilt of a tapped object, in radians, dying away. Reduce Motion keeps objects still.
  static func wobble(_ elapsed: Double, reduceMotion: Bool) -> Float {
    guard !reduceMotion, (0..<wobbleLength).contains(elapsed) else { return 0 }
    return Float(0.05 * exp(-3 * elapsed) * sin(14 * elapsed))
  }

  /// Mochi's reaction to a pet. Reduce Motion keeps only the opened eyes.
  static func pet(_ elapsed: Double, reduceMotion: Bool) -> NookiFrame {
    guard (0..<petLength).contains(elapsed) else { return NookiFrame() }
    let eyesOpen = elapsed < petLength - 0.3
    if reduceMotion { return NookiFrame(eyesOpen: eyesOpen) }
    let rise = min(elapsed / 0.3, (petLength - elapsed) / 0.5)
    let hop = (elapsed - 0.3) / 0.5
    return NookiFrame(
      wake: Float(min(max(rise, 0), 1)),
      eyesOpen: eyesOpen,
      hop: (0...1).contains(hop) ? Float(1 - pow(2 * hop - 1, 2)) * 0.6 : 0
    )
  }
}

extension NookiFrame {
  /// The stronger of two frames, so a reaction shows without disturbing the delivery underneath.
  func combined(with other: NookiFrame) -> NookiFrame {
    NookiFrame(
      wake: max(wake, other.wake),
      eyesOpen: eyesOpen || other.eyesOpen,
      note: note,
      hop: max(hop, other.hop)
    )
  }
}
