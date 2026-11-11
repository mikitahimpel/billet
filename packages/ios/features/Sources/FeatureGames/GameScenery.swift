import GamesInterface

/// Where a mini-game is played: the room itself, or one of the close-up corners. The game's scene
/// switch offers the ones that suit it, in this order.
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

  /// The first is where the game starts.
  public static func options(for game: MiniGame) -> [GameScenery] {
    switch game {
    case .feed, .water: [.kitchen]
    case .brush: [.rug, .kitchen]
    case .laser: [.room]
    }
  }

  /// Where `game` starts: the place last picked for it, if it still offers it.
  public static func start(_ game: MiniGame, last: GameScenery?) -> GameScenery {
    let options = options(for: game)
    if let last, options.contains(last) { return last }
    return options[0]
  }
}
