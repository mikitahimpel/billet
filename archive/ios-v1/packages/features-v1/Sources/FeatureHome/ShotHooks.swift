import Foundation

/// Launch arguments that put Home in a state for screenshots, silent otherwise.
///
/// `-billet.openNeeds <seconds>` opens the cat's needs card that long after Home appears.
/// `-billet.feed <seconds>` feeds the cat from the card that long after Home appears, as its Feed
/// button does.
enum ShotHooks {
  /// When to open the needs card, or `nil` to leave it closed.
  static let openNeeds = delay("billet.openNeeds")
  /// When to feed the cat, or `nil` to leave it be.
  static let feed = delay("billet.feed")

  private static func delay(_ key: String) -> Duration? {
    let seconds = UserDefaults.standard.double(forKey: key)
    return seconds > 0 ? .seconds(seconds) : nil
  }
}
