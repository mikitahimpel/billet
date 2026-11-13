import Foundation

/// The arithmetic of a game's camera: how far back it stands to hold the game's points, and the easing that moves it
/// there. Pure, so a framing that holds still can be tested as one.
public enum GameFraming {
  /// How far from the center of `radius`-wide points a camera must stand for them to fill `fill` of the screen's
  /// narrower side. `tanHalf` is that of the vertical field of view, `aspect` the view's width over height, and
  /// `push` 0...1 brings it a little closer.
  public static func distance(
    radius: Float, tanHalf: Float, aspect: Float, fill: Float, push: Float
  ) -> Float {
    let narrow = tanHalf * min(aspect, 1)
    return max(radius, 0.05) / (narrow * fill) * (1 - 0.1 * push)
  }

  /// `value` moved toward `target` by `rate` per second, the same however the seconds are cut into frames.
  public static func smooth(_ value: Float, toward target: Float, dt: Float, rate: Float) -> Float {
    guard dt > 0 else { return value }
    let next = value + (target - value) * (1 - exp(-rate * dt))
    return abs(target - next) < 0.0005 ? target : next
  }
}
