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
  /// What the room's own frame loop draws at while something moves and while nothing does, in frames a second, and the
  /// pixels it draws across each point. A `RealityView` has neither.
  public var activeRate: Int
  public var idleRate: Int
  public var scale: Double
  /// The glow pass, the sun's shadow map and every point light but the widest.
  public var bloom: Bool
  public var sunShadow: Bool
  public var widestLightOnly: Bool
  /// Stops of ambient light added to make up for the glow pass being off.
  public var ambientLift: Double
  /// How many times longer the flame, candle and bulbs wait between steps.
  public var pulseSlowdown: Double

  public init(
    antialiasing: Bool = false, hdr: Bool = true, splatRate: Int = 0, activeRate: Int = 60,
    idleRate: Int = 30, scale: Double = 2, bloom: Bool = true, sunShadow: Bool = true,
    widestLightOnly: Bool = false, ambientLift: Double = 0, pulseSlowdown: Double = 1
  ) {
    self.antialiasing = antialiasing
    self.hdr = hdr
    self.splatRate = splatRate
    self.activeRate = activeRate
    self.idleRate = idleRate
    self.scale = scale
    self.bloom = bloom
    self.sunShadow = sunShadow
    self.widestLightOnly = widestLightOnly
    self.ambientLift = ambientLift
    self.pulseSlowdown = pulseSlowdown
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

  /// The piece under the finger, while a drag carries it; a chosen piece at rest is none.
  public var dragged: String? {
    switch mode {
    case .arranging(let selected?, _, .some): selected
    case .showing, .arranging: nil
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
  /// The player's choice for the room's lamps: on, off, or nil to follow the hour. The Bedroom lights its lamps and
  /// fairy lights by night on its own; this is the way to have them by day or to put them out.
  public var lights: Bool?
  /// The lamps ease to their new state; off, they change at once (Reduce Motion).
  public var lightsFade: Bool

  public init(
    scene: RoomScene, coat: CatCoat, visibility: RoomVisibility, catName: String = "Mochi",
    catPronouns: CatPronouns = .unchosen, partnerHere: Bool = false, motes: Bool = false,
    sway: Bool = true,
    decor: RoomDecor = RoomDecor(), rendering: RoomRendering = RoomRendering(), lights: Bool? = nil,
    lightsFade: Bool = true
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
    self.lights = lights
    self.lightsFade = lightsFade
  }
}
