import Foundation

/// Moves choices saved for scenes and rooms the app no longer has to the one left: the Nooki
/// scene, in its Window Seat room.
///
/// A choice of a flat scene (Little House or Rooftop), or no choice at all, becomes the kept
/// scene. A room style picked in Labs while there were three (Sunset Lamp, the Nooki diorama, or
/// Window Seat itself) is forgotten. The room chosen in Labs now is kept in its own file
/// (``WidgetFeaturesStore/homeRoomFileName``), which this never touches. Running it again changes
/// nothing.
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
