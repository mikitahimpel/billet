import Foundation
import Wire

/// The four mini-games, each started from the need it fills.
public enum MiniGame: String, CaseIterable, Hashable, Sendable {
  case feed, water, laser, brush

  public var title: String {
    switch self {
    case .feed: "Weigh the food"
    case .water: "Fresh water"
    case .laser: "Laser dot"
    case .brush: "Brush"
    }
  }

  /// The server's id for it in `GamePlayed`.
  public var gameId: String { rawValue }
}

/// How a finished game went, for the journal and the toast. There is no losing.
public struct GameResult: Equatable, Sendable {
  public let game: MiniGame
  /// 0...100: how close to the target it came, or 100 when there is nothing to aim at.
  public let score: Int
  /// The meal's weight, for `feed`.
  public let grams: Int?

  public init(game: MiniGame, score: Int, grams: Int? = nil) {
    self.game = game
    self.score = min(max(score, 0), 100)
    self.grams = grams
  }

  /// A feed that hit `target` with `food` in the bowl: 100 on the gram, less for each gram off.
  public static func feed(target: Int, food: Double) -> GameResult {
    let grams = Int(food.rounded())
    return GameResult(game: .feed, score: 100 - 10 * abs(grams - target), grams: grams)
  }

  /// The care itself where a need calls for it, and the game, which pays the coins (the server
  /// caps them by day).
  public var events: [CatEvent] {
    let played = CatEvent.gamePlayed(game: game.gameId, score: score, won: true)
    switch game {
    case .feed: return [grams.map { .fed(grams: min(max($0, 1), 500)) }, played].compactMap { $0 }
    case .water: return [played]
    case .laser: return [played]
    case .brush: return [.petted, played]
    }
  }

  /// The toast's line.
  public var line: String {
    switch game {
    case .feed: score == 100 ? "Exactly right. Dinner's served" : "Close enough. Dinner's served"
    case .water: score >= 80 ? "Right on the line. Fresh water" : "Fresh water"
    case .laser: "Played out"
    case .brush: "Soft and shiny"
    }
  }
}
