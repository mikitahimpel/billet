import GamesInterface

extension GameResult {
  public static func water(_ bowl: WaterBowl) -> GameResult {
    let off = abs(bowl.level - WaterBowl.line) / WaterBowl.band
    let spilled = bowl.puddle > WaterBowl.dry
    return GameResult(
      game: .water, score: Int((100 - 40 * off - (spilled ? 40 : 0)).rounded()), tooMuch: spilled)
  }
}
