import Foundation
import Persistence
import Testing

@testable import UsInterface

/// Day, month and year milestones count from the pair's start; an unpaired phone has none.
@Suite struct MilestoneTests {
  private let path = "Tests/\(UUID().uuidString)-us.json"
  private let start = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!

  private func cleanUp() {
    SharedFile.flush()
    try? FileManager.default.removeItem(at: SharedFile.url(path))
  }

  private func isMilestone(_ row: Upcoming) -> Bool { row.source == .milestone }

  @Test func withoutAStartThereAreNoMilestones() throws {
    defer { cleanUp() }
    let us = UsStore(file: path)
    let year = try #require(Calendar.current.dateInterval(of: .year, for: start))
    #expect(!us.upcoming(togetherSince: nil, from: start).contains(where: isMilestone))
    #expect(!us.occurrences(togetherSince: nil, in: year).contains(where: isMilestone))
    #expect(us.upcoming(togetherSince: start, from: start).contains(where: isMilestone))
    #expect(us.occurrences(togetherSince: start, in: year).contains(where: isMilestone))
  }
}
