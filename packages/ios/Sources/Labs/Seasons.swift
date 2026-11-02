import Foundation

/// The season outside, by the calendar alone. Nothing to do and nothing to buy: the house just
/// changes with the year. It follows the northern hemisphere's months.
public enum Season: CaseIterable, Sendable {
  case spring
  case summer
  case autumn
  case winter

  public struct Look: Equatable, Sendable {
    public let season: Season
    /// How far through the season it is, from 0 on its first day to just under 1 on its last.
    public let progress: Double
  }

  public static func look(on date: Date, calendar: Calendar) -> Look {
    let month = calendar.component(.month, from: date)
    let season: Season
    let first: Int
    switch month {
    case 3...5: (season, first) = (.spring, 3)
    case 6...8: (season, first) = (.summer, 6)
    case 9...11: (season, first) = (.autumn, 9)
    default: (season, first) = (.winter, 12)
    }
    let seasonMonth = (month - first + 12) % 12
    let day = calendar.component(.day, from: date)
    let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    return Look(
      season: season, progress: (Double(seasonMonth) + Double(day - 1) / Double(daysInMonth)) / 3)
  }

  /// Leaves still on the autumn branch, from eight down to one. Other seasons have none.
  public static func leaves(_ look: Look) -> Int {
    guard look.season == .autumn else { return 0 }
    return max(1, Int((8 * (1 - look.progress)).rounded(.up)))
  }

  /// Blossoms on the spring branch, from two up to nine.
  public static func blossoms(_ look: Look) -> Int {
    guard look.season == .spring else { return 0 }
    return 2 + Int((7 * look.progress).rounded(.down))
  }

  /// How deep the snow lies on the sill, 0 to 1. None outside winter.
  public static func snowDepth(_ look: Look) -> Double {
    guard look.season == .winter else { return 0 }
    // Builds up, then holds: the whole depth by the middle of the season.
    return min(1, 0.25 + look.progress * 1.5)
  }
}
