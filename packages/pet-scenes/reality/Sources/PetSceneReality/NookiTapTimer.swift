import Foundation

/// Tells a double tap from two taps. Single taps act at once, so nothing waits to see if a second
/// one comes.
struct NookiTapTimer {
  static let window: TimeInterval = 0.35

  private var lastTap: TimeInterval?

  mutating func isDoubleTap(at time: TimeInterval) -> Bool {
    if let lastTap, time - lastTap <= Self.window {
      self.lastTap = nil
      return true
    }
    lastTap = time
    return false
  }
}
