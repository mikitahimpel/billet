import DecorInterface

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

/// Which pieces stand where, and whether the player is arranging them.
public struct RoomDecor: Equatable, Sendable {
  public enum Mode: Equatable, Sendable {
    case showing
    /// The pieces are individually addressable. `fits` is false while a dragged piece is somewhere it
    /// does not fit.
    case arranging(selected: String?, fits: Bool)
  }

  public var layout: DecorLayout
  public var mode: Mode

  public init(layout: DecorLayout = DecorLayout(), mode: Mode = .showing) {
    self.layout = layout
    self.mode = mode
  }

  public var isArranging: Bool {
    switch mode {
    case .showing: false
    case .arranging: true
    }
  }
}

/// Everything the room is told to show. The host takes one of these and nothing else, and
/// re-evaluates only when it changes.
public struct RoomInput: Equatable, Sendable {
  public var scene: RoomScene
  public var coat: CatCoat
  public var visibility: RoomVisibility
  /// What VoiceOver calls her.
  public var catName: String
  /// The partner has the app open on their phone.
  public var partnerHere: Bool
  /// The dust drifting through the room. Its particles are stepped every frame the room is drawn,
  /// so Labs can take them away.
  public var motes: Bool
  /// The room turning slowly under the sun and its lights pulsing. Off, nothing in it moves but the cat, so a
  /// still frame can be told from a swaying one.
  public var sway: Bool
  public var decor: RoomDecor

  public init(
    scene: RoomScene, coat: CatCoat, visibility: RoomVisibility, catName: String = "Mochi",
    partnerHere: Bool = false, motes: Bool = true, sway: Bool = true,
    decor: RoomDecor = RoomDecor()
  ) {
    self.scene = scene
    self.coat = coat
    self.visibility = visibility
    self.catName = catName
    self.partnerHere = partnerHere
    self.motes = motes
    self.sway = sway
    self.decor = decor
  }
}
