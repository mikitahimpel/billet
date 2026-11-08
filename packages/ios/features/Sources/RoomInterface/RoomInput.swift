/// Which of Mochi's rooms the host shows.
public enum RoomScene: Equatable, Sendable {
  case home
  case city
  /// The corkboard room behind the Moments tab.
  case board
}

public enum RoomVisibility: Equatable, Sendable {
  case visible
  /// A sheet, the canvas or the Inbox over it: not drawn, its last frame kept for the way back.
  case covered
  /// Another tab or the background: not drawn.
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
