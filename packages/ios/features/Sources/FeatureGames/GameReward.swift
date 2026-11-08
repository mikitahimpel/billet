import GamesInterface

extension GameResult {
  public static func water(_ bowl: WaterBowl) -> GameResult {
    let off = abs(bowl.level - WaterBowl.line) / WaterBowl.band
    let spill = bowl.puddle > WaterBowl.dry ? 40.0 : 0
    return GameResult(game: .water, score: Int((100 - 40 * off - spill).rounded()))
  }
}
