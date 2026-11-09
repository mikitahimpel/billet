/// Where the cat looks during a game: at the finger while it is down, otherwise mostly at the
/// player, with a glance of her own now and then so she doesn't stare.
public struct GameGaze: Equatable, Sendable {
  public enum Look: Equatable, Sendable {
    case finger
    case player
    /// Her own glances.
    case free
  }

  /// Seconds at the player, then seconds free, while no finger is down.
  public static let atPlayer: Double = 3.5
  public static let away: Double = 1.4

  private var clock: Double = 0

  public init() {}

  /// After `dt` seconds, with a finger on the screen or not.
  public mutating func update(dt: Double, touching: Bool) -> Look {
    if touching {
      clock = 0
      return .finger
    }
    clock += max(dt, 0)
    let cycle = clock.truncatingRemainder(dividingBy: Self.atPlayer + Self.away)
    return cycle < Self.atPlayer ? .player : .free
  }

  /// Something went well: she looks up at the player from now.
  public mutating func pleased() { clock = 0 }
}
