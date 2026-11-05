import Foundation

/// What the cat is called: the name given in onboarding, Mochi until then. Kept in the app group so the widgets use
/// it too; the server gets it as the `cat_name` answer.
nonisolated enum CatProfile {
    static let nameKey = "catName"
    static let defaultName = "Mochi"
    /// The server's limit for the `cat_name` answer.
    static let nameLimit = 24
    /// Stands for the cat's name in bundled copy, such as DateIdeas.json.
    static let placeholder = "{cat}"

    /// UserDefaults is thread-safe, though the SDK doesn't mark it Sendable.
    nonisolated(unsafe) static let store = UserDefaults(suiteName: AppGroup.id) ?? .standard

    static func name(in defaults: UserDefaults = store) -> String {
        let saved = defaults.string(forKey: nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? defaultName : saved
    }

    /// The coat picked in onboarding, mirrored here from the app's own defaults (`CatCoat.key`) so the widgets can
    /// dress her in it. Holds the coat's raw value; nil until the app first mirrors it.
    static let coatKey = "catCoat"

    /// The image of her round portrait in her coat: the bundled `MochiPortrait` for the grey tabby or an unknown coat.
    static func avatar(in defaults: UserDefaults = store) -> String {
        let coats = ["ginger", "cream", "tuxedo", "black", "calico"]
        guard let coat = defaults.string(forKey: coatKey), coats.contains(coat) else { return "MochiPortrait" }
        return "MochiPortrait-\(coat)"
    }

    /// `text` with every `placeholder` replaced by the cat's name.
    static func named(_ text: String) -> String {
        text.replacingOccurrences(of: placeholder, with: name())
    }

    /// Builds before the widgets knew the name kept it in the app's own defaults; move it over once.
    static func moveToAppGroup() {
        let group = store
        guard group != .standard, group.string(forKey: nameKey) == nil,
              let old = UserDefaults.standard.string(forKey: nameKey) else { return }
        group.set(old, forKey: nameKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }
}
