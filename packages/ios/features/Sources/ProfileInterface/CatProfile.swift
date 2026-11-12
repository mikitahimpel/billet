import Foundation
import Persistence
import Pet

/// Mochi until named in onboarding. In the app group so the widgets use it too; the server gets it as `cat_name`.
public enum CatProfile {
  public static let nameKey = "catName"
  public static let defaultName = "Mochi"
  /// The server's limit for the `cat_name` answer.
  public static let nameLimit = 24
  /// Stands for the cat's name in bundled and server copy, such as the date catalog.
  public static let placeholder = "{cat}"

  /// UserDefaults is thread-safe, though the SDK doesn't mark it Sendable.
  nonisolated(unsafe) public static let store = UserDefaults(suiteName: AppGroup.id) ?? .standard

  public static func name(in defaults: UserDefaults = store) -> String {
    let saved =
      defaults.string(forKey: nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return saved.isEmpty ? defaultName : saved
  }

  /// "she", "he" or "they", as the pair chose; absent until then.
  public static let pronounsKey = "catPronouns"

  /// What the pair chose, or nil until either did.
  public static func chosenPronouns(in defaults: UserDefaults = store) -> CatPronouns? {
    defaults.string(forKey: pronounsKey).flatMap(CatPronouns.init(rawValue:))
  }

  /// How the app words the cat: the choice, or `they` until there is one. The widgets read it here too.
  public static func pronouns(in defaults: UserDefaults = store) -> CatPronouns {
    chosenPronouns(in: defaults) ?? .unchosen
  }

  public static func setPronouns(_ pronouns: CatPronouns?, in defaults: UserDefaults = store) {
    if let pronouns {
      defaults.set(pronouns.rawValue, forKey: pronounsKey)
    } else {
      defaults.removeObject(forKey: pronounsKey)
    }
  }

  /// The coat picked in onboarding, mirrored here from the app's own defaults (`CatCoat.key`) so the widgets can
  /// dress her in it. Holds the coat's raw value; nil until the app first mirrors it.
  public static let coatKey = "catCoat"

  /// The image of her round portrait in her coat: the bundled `MochiPortrait` for the grey tabby or an unknown coat.
  public static func avatar(in defaults: UserDefaults = store) -> String {
    let coats = ["ginger", "cream", "tuxedo", "black", "calico"]
    guard let coat = defaults.string(forKey: coatKey), coats.contains(coat) else {
      return "MochiPortrait"
    }
    return "MochiPortrait-\(coat)"
  }

  public static func named(_ text: String) -> String {
    text.replacingOccurrences(of: placeholder, with: name())
  }

  /// Builds before the widgets knew the name kept it in the app's own defaults; move it over once.
  public static func moveToAppGroup() {
    let group = store
    guard group != .standard, group.string(forKey: nameKey) == nil,
      let old = UserDefaults.standard.string(forKey: nameKey)
    else { return }
    group.set(old, forKey: nameKey)
    UserDefaults.standard.removeObject(forKey: nameKey)
  }
}
