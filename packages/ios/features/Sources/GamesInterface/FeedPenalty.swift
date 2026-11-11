import Foundation

/// What a bowl poured past her portion costs. The portion's zone is `target` plus or minus the
/// tolerance; past it the bag still pours, up to a hard cap, and each tier of the table takes more.
public struct FeedPenalty: Equatable, Sendable {
  /// The least and most grams a portion can be.
  public static let portions = 25...60

  /// One row: a bowl at most `upTo` of the way through the overfeed room, as a share, scores `score`.
  public struct Tier: Equatable, Sendable {
    public let upTo: Double
    public let score: Int

    public init(upTo: Double, score: Int) {
      self.upTo = upTo
      self.score = score
    }
  }

  public static let tiers = [Tier(upTo: 0.5, score: 30), Tier(upTo: 1, score: 0)]

  /// What the game scores a bowl in this tier.
  public let score: Int
  /// The tier, 0 for the first.
  public let tier: Int

  public init(score: Int, tier: Int) {
    self.score = score
    self.tier = tier
  }

  public static func portion(_ target: Int) -> Int {
    min(max(target, portions.lowerBound), portions.upperBound)
  }

  /// Grams either side of the target that still count: 2, or 5 % of a big portion.
  public static func tolerance(target: Int) -> Int {
    target > 40 ? max(2, Int((Double(target) * 0.05).rounded())) : 2
  }

  /// Grams past the zone the bag keeps pouring before it stops.
  public static func room(target: Int) -> Int { max(6, target / 4) }

  /// The most grams the bowl takes.
  public static func hardCap(target: Int) -> Int {
    let target = portion(target)
    return target + tolerance(target: target) + room(target: target)
  }

  /// The row for `food` grams (non-finite or negative counts as none, past the cap as the cap), or nil
  /// while it is in or under the zone.
  public static func over(target: Int, food: Double) -> FeedPenalty? {
    let target = portion(target)
    let grams = Int(
      min(max(food.isFinite ? food : 0, 0), Double(hardCap(target: target))).rounded())
    let past = grams - target - tolerance(target: target)
    guard past > 0 else { return nil }
    let share = Double(past) / Double(room(target: target))
    let index = tiers.firstIndex { share <= $0.upTo } ?? tiers.count - 1
    return FeedPenalty(score: tiers[index].score, tier: index)
  }
}
