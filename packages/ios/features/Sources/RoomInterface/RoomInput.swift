/// Which of Mochi's rooms the host shows.
public enum RoomScene: Equatable, Sendable {
  case home
  case city
  /// The corkboard room behind the Moments tab.
  case board
}

public enum RoomVisibility: Equatable, Sendable {
  case visible
  /// Another tab or a sheet over it: its view stays, drawing an empty scene, so the way back needs
  /// no new view. Under a sheet its last frame is shown over it.
  case parked
  /// The drawing canvas over it, which takes the room out of the window: not drawn, its last frame
  /// kept for the way back.
  case covered
  /// The background, or another tab under the canvas: not drawn.
  case hidden
}

/// Everything the room is told to show. The host takes one of these and nothing else, and
/// re-evaluates only when it changes.
public struct RoomInput: Equatable, Sendable {
  public var scene: RoomScene
  public var coat: CatCoat
  public var visibility: RoomVisibility

  public init(scene: RoomScene, coat: CatCoat, visibility: RoomVisibility) {
    self.scene = scene
    self.coat = coat
    self.visibility = visibility
  }
}
