import Pet

/// What the pair has done for the pet, as a scene shows it. The host fills this in from `Pet`.
public struct PetPlayState: Hashable, Sendable {
  public enum Treat: Hashable, Sendable {
    case neither
    case waitingOnPartner
    case waitingOnMe
    case fed
  }

  public var treat: Treat
  public var streak: Int
  /// Counts up each time the partner's pet arrives. A scene reacts to each change.
  public var petsReceived: Int

  /// What the shop has put into the room, for a scene that can draw it.
  public var room: RoomLayout
  /// Counts up each time the pair gives the cat a treat from the closet, and `lastTreat` is which.
  public var treatsUsed: Int
  public var lastTreat: ShopItem.ID?
  /// What the pet's needs ask of its behaviour, or nil when its life is not switched on.
  public var life: LifeDrive?
  /// The needs for a scene to show in the room itself: the bowl, a toy, the lamp's warmth. Nil
  /// when that variant is off.
  public var lifeNeeds: PetNeeds?
  /// What the cat's brain asks of the cat now, or nil when the brain is off and the scene picks
  /// the cat's clips itself.
  public var brain: CatBrainFrame?
  /// How many times faster than real time the brain's clock runs, for a scene that should jump
  /// rather than walk.
  public var brainSpeed: Double
  /// Where the room's light switch stands, the same in both partners' rooms.
  public var light: RoomLight

  public init(
    treat: Treat = .neither, streak: Int = 0, petsReceived: Int = 0,
    room: RoomLayout = RoomLayout(), treatsUsed: Int = 0, lastTreat: ShopItem.ID? = nil,
    life: LifeDrive? = nil, lifeNeeds: PetNeeds? = nil,
    brain: CatBrainFrame? = nil, brainSpeed: Double = 1, light: RoomLight = .standard
  ) {
    self.treat = treat
    self.streak = streak
    self.petsReceived = petsReceived
    self.room = room
    self.treatsUsed = treatsUsed
    self.lastTreat = lastTreat
    self.life = life
    self.lifeNeeds = lifeNeeds
    self.brain = brain
    self.brainSpeed = brainSpeed
    self.light = light
  }
}
