import FeatureInbox
import Foundation
import Testing

@testable import Labs

@Suite struct OnThisDayTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .now
  }

  private func note(_ date: Date) -> NoteRecord {
    NoteRecord(direction: .received, date: date, strokes: [])
  }

  @Test func withoutHistoryThereIsNothing() {
    let notes = [note(date(2026, 10, 30)), note(date(2026, 11, 1))]
    #expect(OnThisDay.pick(from: notes, now: date(2026, 11, 2), calendar: calendar) == nil)
    #expect(OnThisDay.pick(from: [], now: date(2026, 11, 2), calendar: calendar) == nil)
  }

  @Test func aNoteFromTheSameDayAYearAgoIsFound() {
    let old = note(date(2025, 11, 2, 9))
    let pick = OnThisDay.pick(
      from: [old, note(date(2026, 11, 1))], now: date(2026, 11, 2), calendar: calendar)
    #expect(pick == OnThisDay(note: old, span: .year))
  }

  @Test func aMonthAgoIsFoundWhenThereIsNoYear() {
    let old = note(date(2026, 10, 2, 20))
    #expect(OnThisDay.pick(from: [old], now: date(2026, 11, 2), calendar: calendar)?.span == .month)
  }

  @Test func aYearBeatsAMonth() {
    let year = note(date(2025, 11, 2))
    let month = note(date(2026, 10, 2))
    #expect(
      OnThisDay.pick(from: [month, year], now: date(2026, 11, 2), calendar: calendar)?.span == .year
    )
  }

  @Test func theNoteNearestMiddayWinsOnAnyOneDay() {
    let early = note(date(2025, 11, 2, 1))
    let near = note(date(2025, 11, 2, 11))
    #expect(
      OnThisDay.pick(from: [early, near], now: date(2026, 11, 2), calendar: calendar)?.note == near)
  }

  @Test func theEndOfALongMonthFindsTheNearestEarlierDay() {
    // A month before 31 March is 28 February.
    let old = note(date(2026, 2, 28))
    #expect(OnThisDay.pick(from: [old], now: date(2026, 3, 31), calendar: calendar)?.span == .month)
  }

  @Test func aLeapDayLooksBackToTheLastFebruaryDayOfTheYearBefore() {
    let old = note(date(2027, 2, 28))
    #expect(OnThisDay.pick(from: [old], now: date(2028, 2, 29), calendar: calendar)?.span == .year)
  }
}
