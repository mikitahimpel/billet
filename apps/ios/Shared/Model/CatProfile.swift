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
