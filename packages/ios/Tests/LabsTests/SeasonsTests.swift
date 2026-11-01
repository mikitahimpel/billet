import Foundation
import Testing

@testable import Labs

@Suite struct SeasonsTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    return calendar
  }

  private func look(_ month: Int, _ day: Int = 1) -> Season.Look {
    Season.look(
      on: calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)) ?? .now,
      calendar: calendar)
  }

  @Test func everyMonthBelongsToTheRightSeason() {
    let expected: [Season] = [
      .winter, .winter, .spring, .spring, .spring, .summer, .summer, .summer, .autumn, .autumn,
      .autumn, .winter,
    ]
    #expect((1...12).map { look($0).season } == expected)
  }

  @Test func progressRunsFromZeroToJustUnderOneInEachSeason() {
    for first in [3, 6, 9, 12] {
      #expect(look(first).progress == 0)
    }
    #expect(look(5, 31).progress < 1)
    #expect(look(5, 31).progress > 0.95)
    #expect(look(2, 28).progress > 0.95)
  }

  @Test func theAutumnBranchLosesLeavesThroughTheSeason() {
    let counts = [look(9), look(10), look(11), look(11, 30)].map(Season.leaves)
    #expect(counts == counts.sorted(by: >))
    #expect(counts.first == 8)
    #expect(counts.allSatisfy { $0 >= 1 })
    #expect(Season.leaves(look(6)) == 0)
  }

  @Test func theSpringBranchGainsBlossoms() {
    let counts = [look(3), look(4), look(5), look(5, 31)].map(Season.blossoms)
    #expect(counts == counts.sorted())
    #expect(counts.first == 2)
    #expect(counts.last ?? 0 <= 9)
    #expect(Season.blossoms(look(10)) == 0)
  }

  @Test func theSnowBuildsUpAndStaysInWinterOnly() {
    #expect(Season.snowDepth(look(12)) == 0.25)
    #expect(Season.snowDepth(look(1)) > Season.snowDepth(look(12)))
    #expect(Season.snowDepth(look(2, 20)) == 1)
    #expect(Season.snowDepth(look(7)) == 0)
  }

  @Test func theYearTurnsFromDecemberToJanuary() {
    #expect(look(12, 31).season == .winter)
    #expect(look(1, 1).season == .winter)
    #expect(look(1).progress > look(12, 31).progress)
  }
}
