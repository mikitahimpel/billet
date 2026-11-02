import Foundation

/// Moves a scene choice saved when the app still had its flat scenes, Little House and Rooftop, to
/// the one scene left.
///
/// A choice of a flat scene, or no choice at all (Little House came first, so it showed until
/// someone chose), drops any room picked in Labs meanwhile, which that person never saw, so the
/// room is the standard Window Seat, or the pair's test room. Running it again changes nothing: it
/// saves the kept scene as the choice, and a later Labs choice stays.
public enum FlatSceneMigration {
  /// The ids the flat scenes were saved under.
  public static let removedSceneIDs: Set<String> = ["little-house", "rooftop"]

  public static func run(
    defaults: UserDefaults, choiceKey: String, keptSceneID: String, store: WidgetFeaturesStore
  ) {
    let stored = defaults.string(forKey: choiceKey)
    guard stored.map(removedSceneIDs.contains) ?? true else { return }
    // The choice moves only once the room is cleared, so a failed removal is tried next launch.
    guard (try? store.clearRoomStyle()) != nil else { return }
    defaults.set(keptSceneID, forKey: choiceKey)
  }
}
