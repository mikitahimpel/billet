import FeatureInbox
import Foundation
import Testing

@testable import Labs

@Suite struct SundayPostTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    return calendar
  }

  private func date(_ day: Int, hour: Int = 12) -> Date {
    // November 2026: the 1st is a Sunday, so the 2nd is a Monday and the 8th a Sunday.
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)) ?? .now
  }

  private func note(_ direction: NoteRecord.Direction, _ day: Int, hour: Int = 12) -> NoteRecord {
    NoteRecord(direction: direction, date: date(day, hour: hour), strokes: [])
  }

  @Test func onASundayThePageIsTheWeekThatEndsToday() throws {
    let notes = [note(.sent, 2), note(.received, 4), note(.sent, 8, hour: 9), note(.sent, 9)]
    let post = try #require(
      SundayPost.page(from: notes, now: date(8, hour: 20), calendar: calendar))
    #expect(post.notes.count == 3)
    #expect(post.sent == 2 && post.received == 1)
    #expect(calendar.component(.weekday, from: post.weekStart) == 2)
    #expect(calendar.component(.weekday, from: post.weekEnd) == 1)
  }

  @Test func onOtherDaysItIsTheLastFinishedWeek() throws {
    let notes = [note(.sent, 2), note(.received, 6), note(.sent, 10)]
    let post = try #require(SundayPost.page(from: notes, now: date(11), calendar: calendar))
    #expect(post.notes.map(\.id) == [notes[0].id, notes[1].id])
  }

  @Test func aPreviewShowsTheWeekSoFar() throws {
    let notes = [note(.sent, 10), note(.received, 11)]
    #expect(SundayPost.page(from: notes, now: date(12), calendar: calendar) == nil)
    let post = try #require(
      SundayPost.page(from: notes, now: date(12), calendar: calendar, preview: true))
    #expect(post.notes.count == 2)
  }

  @Test func aQuietWeekHasNoPage() {
    #expect(SundayPost.page(from: [], now: date(8), calendar: calendar) == nil)
  }

  @Test func aPageHoldsTheNewestSixInOrderButCountsThemAll() throws {
    let notes = (2...9).map { note(.sent, $0 > 8 ? 8 : $0, hour: $0) }
    let post = try #require(
      SundayPost.page(from: notes, now: date(8, hour: 23), calendar: calendar))
    #expect(post.notes.count == SundayPost.capacity)
    #expect(post.sent == notes.count)
    #expect(post.notes == post.notes.sorted { $0.date < $1.date })
  }

  @Test func theWeekRunsMondayThroughSundayWhateverTheLocaleSays() throws {
    var american = calendar
    american.firstWeekday = 1
    let notes = [note(.sent, 1, hour: 10)]
    let post = SundayPost.page(from: notes, now: date(1, hour: 20), calendar: american)
    #expect(post?.notes.count == 1)
    #expect(SundayPost.isSunday(date(1), calendar: american))
    #expect(!SundayPost.isSunday(date(2), calendar: american))
  }
}
