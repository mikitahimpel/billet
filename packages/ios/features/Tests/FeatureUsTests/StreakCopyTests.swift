import Foundation
import Testing
import UsInterface

@testable import FeatureUs

@Suite struct StreakCopyTests {
  nonisolated private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }()

  /// Noon, so a day either way is the day before or after.
  nonisolated private static let today =
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12)) ?? .distantPast

  private static func day(_ offset: Int) -> Date {
    calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: today) ?? today)
  }

  private func copy(_ streak: LoveStreak, daysTogether: Int?) -> StreakCopy {
    StreakCopy(
      streak: streak, on: Self.today, calendar: Self.calendar, daysTogether: daysTogether,
      partner: "Alex", cat: "Mochi")
  }

  @Test func unpairedWithNoStreakLeavesTheWordsToTheInvitation() {
    let copy = copy(LoveStreak(), daysTogether: nil)
    #expect(!copy.isPaired)
    #expect(copy.line == nil)
    #expect(copy.days == 0)
    #expect(copy.next == 3)
    #expect(copy.spoken == "Waiting for your partner. 0-day streak, 3 days to the 3-day badge.")
  }

  @Test func unpairedWithAStreakOfOnesOwnSaysWhereItStands() throws {
    let copy = copy(LoveStreak(count: 2, lastDay: Self.day(0), best: 2), daysTogether: nil)
    let line = try #require(copy.line)
    #expect(line.lead == "Day 2 is in.")
    #expect(line.rest == " Badge at day 3.")
  }

  @Test func pairedAndColdAsksForTheFlame() throws {
    let copy = copy(LoveStreak(), daysTogether: 128)
    let line = try #require(copy.line)
    #expect(line.lead + line.rest == "Light the flame together today.")
    #expect(copy.spoken == "128 days together. 0-day streak, 3 days to the 3-day badge.")
  }

  @Test func theFirstDayTogetherIsSingular() {
    let copy = copy(LoveStreak(count: 1, lastDay: Self.day(0), best: 1), daysTogether: 1)
    #expect(copy.spoken == "1 day together. 1-day streak, 2 days to the 3-day badge.")
  }

  @Test func aDayThatCountsNamesTheNextBadge() throws {
    let copy = copy(LoveStreak(count: 6, lastDay: Self.day(0), best: 6), daysTogether: 40)
    let line = try #require(copy.line)
    #expect(copy.status == .done)
    #expect(line.lead + line.rest == "Day 6 is in. Badge at day 7.")
    #expect(copy.spoken == "40 days together. 6-day streak, 1 day to the 7-day badge.")
  }

  @Test func pastTheLastBadgeThereIsNoNext() throws {
    let copy = copy(LoveStreak(count: 400, lastDay: Self.day(0), best: 400), daysTogether: 500)
    let line = try #require(copy.line)
    #expect(copy.next == nil)
    #expect(line.rest == " See you tomorrow.")
    #expect(copy.spoken == "500 days together. 400-day streak.")
  }

  @Test func thePartnersPartMakesItYourTurn() throws {
    let streak = LoveStreak(count: 4, lastDay: Self.day(-1), best: 4, partner: [Self.day(0)])
    let copy = copy(streak, daysTogether: 40)
    let line = try #require(copy.line)
    #expect(copy.status == .atRisk)
    #expect(copy.turn == .yours)
    #expect(line.lead + line.rest == "Alex did their part. Your turn: pet Mochi or leave a note.")
    #expect(copy.spoken.hasSuffix(" Alex did their part, your turn."))
  }

  @Test func yourPartWaitsForThePartner() throws {
    let streak = LoveStreak(count: 4, lastDay: Self.day(-1), best: 4, mine: [Self.day(0)])
    let copy = copy(streak, daysTogether: 40)
    let line = try #require(copy.line)
    #expect(copy.turn == .partners)
    #expect(line.lead + line.rest == "You did your part. The flame lights when Alex does theirs.")
    #expect(copy.spoken.hasSuffix(" Waiting for Alex."))
  }

  @Test func atRiskWithNobodysPartAsksBoth() throws {
    let copy = copy(LoveStreak(count: 4, lastDay: Self.day(-1), best: 4), daysTogether: 40)
    let line = try #require(copy.line)
    #expect(line.lead + line.rest == "Keep it going. You both do one small thing today.")
  }

  @Test func aMissedDayOffersTheRestore() throws {
    let copy = copy(LoveStreak(count: 5, lastDay: Self.day(-2), best: 5), daysTogether: 40)
    let line = try #require(copy.line)
    #expect(copy.status == .restorable)
    #expect(copy.days == 0)
    #expect(line.lead + line.rest == "You missed a day. You can bring the flame back once a month.")
  }
}
