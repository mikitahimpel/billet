import Foundation
import Pet
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
  /// The bowl went past the portion (feed) or the brim (water): the reward is cut.
  public let tooMuch: Bool
  /// Water spilled and was wiped up again.
  public let spotless: Bool
  /// Something was left on the mat: the reward is cut a little.
  public let messy: Bool

  public init(
    game: MiniGame, score: Int, grams: Int? = nil, tooMuch: Bool = false, spotless: Bool = false,
    messy: Bool = false
  ) {
    self.spotless = spotless
    self.messy = messy
    self.game = game
    self.score = min(max(score, 0), 100)
    self.grams = grams
    self.tooMuch = tooMuch
  }

  /// A feed that hit `target` with `food` in the bowl: 100 on the gram, less for each gram off,
  /// and past the portion's zone the table in ``FeedPenalty`` decides.
  public static func feed(
    target: Int, food: Double, crumbs: Int = 0, spotless: Bool = false
  ) -> GameResult {
    let target = FeedPenalty.portion(target)
    let grams = Int(max(food.isFinite ? food : 0, 0).rounded())
    let penalty = FeedPenalty.over(target: target, food: food)
    let base = penalty?.score ?? max(0, 100 - 10 * abs(grams - target))
    let messy = crumbs > 0
    return GameResult(
      game: .feed, score: messy ? max(0, base - messCost) : base, grams: grams,
      tooMuch: penalty != nil, spotless: spotless && !messy, messy: messy)
  }

  /// Points off a feed that leaves crumbs on the mat.
  public static let messCost = 15

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
  public func line(pronouns: CatPronouns) -> String {
    switch game {
    case .feed:
      if tooMuch {
        let stuffed = pronouns.say(.tooMuchResult)
        if messy { return "\(stuffed), and a little messy" }
        return spotless ? "\(stuffed), but the mat is spotless" : stuffed
      }
      return score == 100 ? "Exactly right. Dinner's served" : "Close enough. Dinner's served"
    case .water:
      if tooMuch { return "A little messy. Fresh water, though" }
      if spotless { return "Spotless. Fresh water" }
      return score >= 80 ? "Right on the line. Fresh water" : "Fresh water"
    case .laser: return "Played out"
    case .brush: return "Soft and shiny"
    }
  }
}
