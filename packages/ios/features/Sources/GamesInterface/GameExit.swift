import Foundation

/// The swipe that leaves a game: down from near the top edge, mostly vertical. Below the band the stages' own drags
/// begin, so they never reach it.
public enum GameExit {
  public static let band: CGFloat = 140
  public static let length: CGFloat = 90

  public static func isSwipe(from start: CGPoint, translation: CGSize) -> Bool {
    start.y < band && translation.height > length && abs(translation.width) < translation.height
  }
}
