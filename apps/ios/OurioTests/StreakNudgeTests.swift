import Design
import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Testing
import UsInterface
@testable import Billet

@Suite struct StreakNudgeTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private static func at(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    /// Counted on each of `days`, November.
    private static func streak(_ days: [Int]) -> LoveStreak {
        var streak = LoveStreak()
        for day in days { streak.record(on: at(day: day, hour: 12), calendar: calendar) }
        return streak
    }

    private static func fire(_ streak: LoveStreak, now: Date) -> Date? {
        StreakNudge.plan(for: streak, catName: "Mochi", now: now, calendar: calendar)?.fire
    }

    @Test func aStreakNotYetCountedTodayIsNudgedThisEvening() {
        let plan = StreakNudge.plan(for: Self.streak([7, 8]), catName: "Mochi", now: Self.at(day: 9, hour: 10),
                                    calendar: Self.calendar)
        #expect(plan == StreakNudge.Plan(
            fire: Self.at(day: 9, hour: 20), title: "Mochi misses you two tonight",
            body: "Do one small thing together before midnight to keep your 2-day streak."))
    }

    @Test func aDayThatCountsMovesTheNudgeToTomorrowEvening() {
        #expect(Self.fire(Self.streak([7, 8, 9]), now: Self.at(day: 9, hour: 10)) == Self.at(day: 10, hour: 20))
    }

    @Test func afterDoingYourPartYouAreNotNudged() {
        var streak = Self.streak([7, 8])
        streak.mark(on: Self.at(day: 9, hour: 9), calendar: Self.calendar)
        #expect(Self.fire(streak, now: Self.at(day: 9, hour: 10)) == nil)
    }

    @Test func whenThePartnerDidTheirsTheNudgeSaysItsYourTurn() {
        var streak = Self.streak([7, 8])
        streak.partner = [Self.calendar.startOfDay(for: Self.at(day: 9, hour: 9))]
        let plan = StreakNudge.plan(for: streak, catName: "Mochi", now: Self.at(day: 9, hour: 10),
                                    calendar: Self.calendar)
        #expect(plan == StreakNudge.Plan(
            fire: Self.at(day: 9, hour: 20), title: "Mochi misses you tonight",
            body: "Your partner did their part. Do yours before midnight to keep your 2-day streak."))
    }

    @Test func pastEightTheAtRiskDayIsNotNudgedAgain() {
        #expect(Self.fire(Self.streak([7, 8]), now: Self.at(day: 9, hour: 21)) == nil)
    }

    @Test(arguments: [
        [Int](),
        [5, 6, 7],
    ])
    func aStreakThatIsOutIsNeverNudged(days: [Int]) {
        #expect(Self.fire(Self.streak(days), now: Self.at(day: 9, hour: 10)) == nil)
    }

    @Test func theSwitchSetBeforeItWasSharedMovesToTheAppGroup() throws {
        let old = try #require(UserDefaults(suiteName: "nudge-old-\(UUID().uuidString)"))
        let group = try #require(UserDefaults(suiteName: "nudge-group-\(UUID().uuidString)"))
        #expect(StreakNudge.isOn(in: group))
        old.set(false, forKey: AppSettings.streakNudgeKey)
        StreakNudge.moveToAppGroup(from: old, to: group)
        #expect(!StreakNudge.isOn(in: group))
        #expect(old.object(forKey: AppSettings.streakNudgeKey) == nil)
        // A switch already in the group wins.
        old.set(true, forKey: AppSettings.streakNudgeKey)
        StreakNudge.moveToAppGroup(from: old, to: group)
        #expect(!StreakNudge.isOn(in: group))
    }
}
