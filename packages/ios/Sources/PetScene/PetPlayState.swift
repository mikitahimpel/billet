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

  public init(
    treat: Treat = .neither, streak: Int = 0, petsReceived: Int = 0,
    room: RoomLayout = RoomLayout(), treatsUsed: Int = 0, lastTreat: ShopItem.ID? = nil
  ) {
    self.treat = treat
    self.streak = streak
    self.petsReceived = petsReceived
    self.room = room
    self.treatsUsed = treatsUsed
    self.lastTreat = lastTreat
  }
}
