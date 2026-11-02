import SwiftUI

/// The app's two speeds. Nothing overshoots: everything moves like a room in the evening.
public enum Motion {
  /// A press or a small state change.
  public static let quick = Animation.easeOut(duration: 0.18)
  /// A screen, a tab or a panel changing.
  public static let spring = Animation.spring(duration: 0.5, bounce: 0.08)
}

extension View {
  /// Animates `value` with `animation`, or with a plain short fade under Reduce Motion.
  public func calmAnimation(
    _ animation: Animation = Motion.spring, value: some Equatable
  ) -> some View {
    modifier(CalmAnimation(animation: animation, value: value))
  }
}

private struct CalmAnimation<Value: Equatable>: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let animation: Animation
  let value: Value

  func body(content: Content) -> some View {
    content.animation(reduceMotion ? .easeInOut(duration: 0.15) : animation, value: value)
  }
}
