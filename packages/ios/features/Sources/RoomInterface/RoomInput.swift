import DecorInterface
import Pet

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

/// What the room's renderer is asked to draw. Each is a cost per pixel, every frame, that a phone's own screen may not
/// show.
public struct RoomRendering: Equatable, Sendable {
  /// Four samples a pixel on the edges of the clay shapes.
  public var antialiasing: Bool
  /// The wide colour range the glow and bloom are drawn in.
  public var hdr: Bool

  /// The splat cat is rewritten and re-sorted at most this many times a second; 0 is every frame.
  public var splatRate: Int

  public init(antialiasing: Bool = false, hdr: Bool = true, splatRate: Int = 0) {
    self.antialiasing = antialiasing
    self.hdr = hdr
    self.splatRate = splatRate
  }
}

/// Which pieces stand where, and whether the player is arranging them.
public struct RoomDecor: Equatable, Sendable {
  public enum Mode: Equatable, Sendable {
    case showing
    /// The pieces are individually addressable. `fits` is false while a dragged piece is somewhere it
    /// does not fit. `ghost` is where the dragged piece stood, drawn as an outline while it is away.
    case arranging(selected: String?, fits: Bool, ghost: Placement? = nil)
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
  public var catPronouns: CatPronouns
  /// The partner has the app open on their phone.
  public var partnerHere: Bool
  /// The dust drifting through the room. Its particles are stepped every frame the room is drawn, so
  /// it is off unless Labs turns it on.
  public var motes: Bool
  /// The room turning slowly under the sun and its lights pulsing. Off, nothing in it moves but the cat, so a
  /// still frame can be told from a swaying one.
  public var sway: Bool
  public var decor: RoomDecor
  public var rendering: RoomRendering

  public init(
    scene: RoomScene, coat: CatCoat, visibility: RoomVisibility, catName: String = "Mochi",
    catPronouns: CatPronouns = .unchosen, partnerHere: Bool = false, motes: Bool = false,
    sway: Bool = true,
    decor: RoomDecor = RoomDecor(), rendering: RoomRendering = RoomRendering()
  ) {
    self.scene = scene
    self.coat = coat
    self.visibility = visibility
    self.catName = catName
    self.catPronouns = catPronouns
    self.partnerHere = partnerHere
    self.motes = motes
    self.sway = sway
    self.decor = decor
    self.rendering = rendering
  }
}
