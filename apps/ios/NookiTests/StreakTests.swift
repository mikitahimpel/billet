import Foundation
import Testing
@testable import Billet

private let cal = Calendar.current
private let day1 = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: day1)! }

@Suite struct LoveStreakTests {
    @Test func firstActionEachDayCounts() {
        var s = LoveStreak()
        s.record(on: day(0))
        s.record(on: day(0).addingTimeInterval(3600))
        s.record(on: day(1))
        #expect(s.current(on: day(1)) == 2)
        #expect(s.status(on: day(1)) == .done)
        #expect(s.status(on: day(2)) == .atRisk)
        #expect(s.current(on: day(2)) == 2)
    }

    @Test func missedDayBreaksAndRestoreBringsItBack() {
        var s = LoveStreak()
        for d in 0..<5 { s.record(on: day(d)) }
        #expect(s.status(on: day(6)) == .restorable)
        #expect(s.current(on: day(6)) == 0)
        s.restore(on: day(6))
        s.record(on: day(6))
        #expect(s.current(on: day(6)) == 6)
        #expect(s.best == 6)
        // The next restore waits a month.
        s.record(on: day(7))
        #expect(s.status(on: day(9)) == .cold)
    }

    @Test func breakingWithoutRestoreStartsOverButKeepsBest() {
        var s = LoveStreak()
        for d in 0..<4 { s.record(on: day(d)) }
        s.record(on: day(10))
        #expect(s.current(on: day(10)) == 1)
        #expect(s.best == 4)
    }

    @Test func milestones() {
        var s = LoveStreak()
        for d in 0..<8 { s.record(on: day(d)) }
        #expect(s.milestone(on: day(7)).reached == 7)
        #expect(s.milestone(on: day(7)).next == 14)
    }
}
