import Foundation
import Persistence

/// What the room last knew of Mochi's needs, written by the app for the widgets: they cannot run her brain, so they
/// read this and let a feed or a pet from the widget itself stand in until the app writes again.
public nonisolated struct CatNeedsGlance: Codable, Hashable, Sendable {
  /// What she can ask for. A low need is an invitation, never a warning.
  public enum Want: String, Codable, CaseIterable, Sendable {
    case food, rest, love, play
  }

  public var full: Double
  public var rested: Double
  public var loved: Double
  public var playful: Double
  /// Below this a need wants something: the brain's own line.
  public var lowBelow: Double
  public var savedAt: Date

  public init(
    full: Double, rested: Double, loved: Double, playful: Double, lowBelow: Double, savedAt: Date
  ) {
    self.full = full
    self.rested = rested
    self.loved = loved
    self.playful = playful
    self.lowBelow = lowBelow
    self.savedAt = savedAt
  }

  /// Older than this, the needs have moved too far to say anything about her.
  public static let freshFor: TimeInterval = 6 * 3600
  /// A meal from the widget keeps her full this long, as far as the widget can tell.
  public static let mealLevel = 0.8
  public static let petGain = 0.2

  private static let file = "Couple/cat-needs.json"

  public static func load() -> CatNeedsGlance? {
    SharedFile.read(CatNeedsGlance.self, from: file)
  }

  public func save() { SharedFile.write(self, to: Self.file) }

  /// Whether a new reading says something the widgets don't already show, so the app writes (and reloads them) only
  /// when she starts or stops wanting something, not on every tick of her needs.
  public func differsForWidgets(from old: CatNeedsGlance?) -> Bool {
    guard let old else { return true }
    return want(at: savedAt) != old.want(at: old.savedAt)
      || savedAt.timeIntervalSince(old.savedAt) > Self.freshFor / 2
  }

  /// The one thing she wants most at `date`, or nil while she is content, the reading is old, or she is asleep.
  /// `fedAt` and `pettedAt` are care given from a widget since the reading.
  public func want(
    at date: Date, asleep: Bool = false, fedAt: Date? = nil, pettedAt: Date? = nil
  ) -> Want? {
    let age = date.timeIntervalSince(savedAt)
    guard !asleep, age >= 0, age < Self.freshFor else { return nil }
    var full = full
    var loved = loved
    if let fedAt, fedAt >= savedAt, fedAt <= date { full = max(full, Self.mealLevel) }
    if let pettedAt, pettedAt >= savedAt, pettedAt <= date { loved = min(1, loved + Self.petGain) }
    let levels: [(Want, Double)] = [
      (.food, full), (.rest, rested), (.love, loved), (.play, playful),
    ]
    guard let lowest = levels.min(by: { $0.1 < $1.1 }), lowest.1 < lowBelow else { return nil }
    return lowest.0
  }
}
