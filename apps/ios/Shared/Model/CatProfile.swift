import Foundation
import Persistence

/// Mochi until named in onboarding. In the app group so the widgets use it too; the server gets it as `cat_name`.
public nonisolated enum CatProfile {
    public static let nameKey = "catName"
    public static let defaultName = "Mochi"
    /// The server's limit for the `cat_name` answer.
    public static let nameLimit = 24
    /// Stands for the cat's name in bundled and server copy, such as the date catalog.
    public static let placeholder = "{cat}"

    /// UserDefaults is thread-safe, though the SDK doesn't mark it Sendable.
    public nonisolated(unsafe) static let store = UserDefaults(suiteName: AppGroup.id) ?? .standard

    public static func name(in defaults: UserDefaults = store) -> String {
        let saved = defaults.string(forKey: nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? defaultName : saved
    }

    /// The coat picked in onboarding, mirrored here from the app's own defaults (`CatCoat.key`) so the widgets can
    /// dress her in it. Holds the coat's raw value; nil until the app first mirrors it.
    public static let coatKey = "catCoat"

    /// The image of her round portrait in her coat: the bundled `MochiPortrait` for the grey tabby or an unknown coat.
    public static func avatar(in defaults: UserDefaults = store) -> String {
        let coats = ["ginger", "cream", "tuxedo", "black", "calico"]
        guard let coat = defaults.string(forKey: coatKey), coats.contains(coat) else { return "MochiPortrait" }
        return "MochiPortrait-\(coat)"
    }

    public static func named(_ text: String) -> String {
        text.replacingOccurrences(of: placeholder, with: name())
    }

    /// Builds before the widgets knew the name kept it in the app's own defaults; move it over once.
    public static func moveToAppGroup() {
        let group = store
        guard group != .standard, group.string(forKey: nameKey) == nil,
              let old = UserDefaults.standard.string(forKey: nameKey) else { return }
        group.set(old, forKey: nameKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }
}
