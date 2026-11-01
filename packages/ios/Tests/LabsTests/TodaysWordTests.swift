import Foundation
import Testing

@testable import Labs

@Suite struct TodaysWordTests {
  @Test func theListIsLongAndCleanAndHasNoRepeats() {
    let all = TodaysWordList.all
    #expect(all.count >= 200)
    #expect(Set(all).count == all.count)
    for word in all {
      #expect(!word.isEmpty && word == word.trimmingCharacters(in: .whitespaces))
      #expect(word.count <= 32)
    }
  }

  @Test func theSameDayGivesTheSameWord() {
    #expect(TodaysWord.word(onDay: "2026-11-02") == TodaysWord.word(onDay: "2026-11-02"))
    #expect(TodaysWord.word(onDay: "2026-11-02") != nil)
  }

  @Test func noWordComesTwiceInAFullRound() {
    var seen = Set<String>()
    var day = DateComponents(
      calendar: Calendar(identifier: .gregorian), year: 2026, month: 1, day: 1)
    for offset in 0..<TodaysWord.count {
      day.day = 1 + offset
      let date = day.calendar?.date(from: day) ?? .now
      let parts = Calendar(identifier: .gregorian).dateComponents(
        [.year, .month, .day], from: date)
      let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
      seen.insert(TodaysWord.word(onDay: key) ?? "")
    }
    #expect(seen.count == TodaysWord.count)
  }

  @Test func consecutiveDaysDiffer() {
    #expect(TodaysWord.word(onDay: "2026-12-31") != TodaysWord.word(onDay: "2027-01-01"))
    #expect(TodaysWord.word(onDay: "2028-02-28") != TodaysWord.word(onDay: "2028-02-29"))
  }

  @Test func dayNumbersCountCalendarDays() {
    #expect(TodaysWord.dayNumber("2000-01-01") == 0)
    #expect(TodaysWord.dayNumber("2000-03-01") == 60)
    #expect(TodaysWord.dayNumber("2001-01-01") == 366)
    #expect(TodaysWord.dayNumber("2026-11-02") == 9_802)
  }

  @Test func textThatIsNotADayGivesNoWord() {
    #expect(TodaysWord.word(onDay: "tomorrow") == nil)
    #expect(TodaysWord.word(onDay: "2026-13-01") == nil)
    #expect(TodaysWord.word(onDay: "") == nil)
  }

  @Test func theCardHidesOnceDismissedOrAnswered() {
    #expect(TodaysWord.isShown(onDay: "2026-11-02", dismissedDay: nil, sentToday: false))
    #expect(TodaysWord.isShown(onDay: "2026-11-02", dismissedDay: "2026-11-01", sentToday: false))
    #expect(!TodaysWord.isShown(onDay: "2026-11-02", dismissedDay: "2026-11-02", sentToday: false))
    #expect(!TodaysWord.isShown(onDay: "2026-11-02", dismissedDay: nil, sentToday: true))
    #expect(!TodaysWord.isShown(onDay: "nope", dismissedDay: nil, sentToday: false))
  }
}
