import Foundation

/// Moves choices for scenes and rooms the app no longer has to the Ourio scene's Window Seat room.
/// A flat scene or no choice becomes the kept scene; a Labs room style is forgotten. Never touches
/// ``WidgetFeaturesStore/homeRoomFileName``; running it again changes nothing.
public enum RemovedScenesMigration {
  /// The ids the flat scenes were saved under.
  public static let removedSceneIDs: Set<String> = ["little-house", "rooftop"]

  public static func run(
    defaults: UserDefaults, choiceKey: String, keptSceneID: String, store: WidgetFeaturesStore
  ) {
    try? store.removeRoomStyle()
    let stored = defaults.string(forKey: choiceKey)
    guard stored.map(removedSceneIDs.contains) ?? true else { return }
    defaults.set(keptSceneID, forKey: choiceKey)
  }
}
