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

  public init(treat: Treat = .neither, streak: Int = 0, petsReceived: Int = 0) {
    self.treat = treat
    self.streak = streak
    self.petsReceived = petsReceived
  }
}
