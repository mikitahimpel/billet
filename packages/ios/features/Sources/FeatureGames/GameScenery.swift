import GamesInterface

/// Where a mini-game is played: the room itself, or one of the close-up corners.
public enum GameScenery: String, CaseIterable, Hashable, Sendable {
  case room, rug, kitchen

  public var title: String {
    switch self {
    case .room: "Room"
    case .rug: "Rug"
    case .kitchen: "Kitchen"
    }
  }

  /// Played in a corner of its own rather than in the room.
  public var isCorner: Bool {
    switch self {
    case .room: false
    case .rug, .kitchen: true
    }
  }

  /// The scenes that suit the game; it is played in the first.
  public static func options(for game: MiniGame) -> [GameScenery] {
    switch game {
    case .feed, .water: [.kitchen]
    case .brush: [.rug, .kitchen]
    case .laser: [.room]
    }
  }

  public static func start(_ game: MiniGame) -> GameScenery { options(for: game)[0] }
}
