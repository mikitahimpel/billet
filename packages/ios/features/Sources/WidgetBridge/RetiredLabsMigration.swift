import Foundation

/// Forgets what removed Labs experiments kept outside the flags file, so nothing of theirs is left
/// on the phone. Their switches are dropped by ``WidgetFeatures/retiredKeys``. Running it again
/// changes nothing.
public enum RetiredLabsMigration {
  /// The `UserDefaults` keys removed experiments wrote: the frame wall, real and fake.
  public static let retiredDefaultsKeys: Set<String> = [
    "labs.framedNotes", "labs.framedNotes.fake",
  ]

  public static func run(defaults: UserDefaults) {
    for key in retiredDefaultsKeys {
      defaults.removeObject(forKey: key)
    }
  }
}
