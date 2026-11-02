import Foundation
import Testing

@testable import FeatureInbox

@Suite struct NoteDateTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  private func date(year: Int) throws -> Date {
    try #require(calendar.date(from: DateComponents(year: year, month: 11, day: 2)))
  }

  private func text(of year: Int) throws -> String {
    let date = try date(year: year)
    return date.formatted(
      NoteDate.style(of: date, now: try self.date(year: 2026), calendar: calendar)
        .locale(Locale(identifier: "en_GB")))
  }

  @Test func aNoteFromThisYearLeavesTheYearOut() throws {
    #expect(try !text(of: 2026).contains("2026"))
  }

  @Test func aNoteFromAnotherYearSaysWhich() throws {
    #expect(try text(of: 2025).contains("2025"))
  }
}
