import SwiftUI

/// The app's two speeds. Everything moves slowly, like a room in the evening.
public enum Motion {
  /// A press or a small state change.
  public static let quick = Animation.easeOut(duration: 0.18)
  /// A screen, tab or panel changing.
  public static let gentle = Animation.easeInOut(duration: 0.35)
  /// A small living response, such as the cat leaning into a pet.
  public static let settle = Animation.spring(duration: 0.45, bounce: 0.15)
}
