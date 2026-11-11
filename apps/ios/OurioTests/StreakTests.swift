import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Testing
import UsInterface
import Wire
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

    @Test func aDayLightsOnceBothPartnersDidTheirPart() {
        var s = LoveStreak()
        s.mark(on: day(0))
        #expect(s.current(on: day(0)) == 0)
        #expect(s.turn(on: day(0)) == .partners)
        s.mark(on: day(0).addingTimeInterval(60))
        #expect(s.mine == [cal.startOfDay(for: day(0))])
        s.partnerMark(on: day(0))
        #expect(s.status(on: day(0)) == .done)
        #expect(s.turn(on: day(0)) == nil)
        #expect(s.mine.isEmpty && s.partner.isEmpty)

        s.partnerMark(on: day(1))
        #expect(s.turn(on: day(1)) == .yours)
        #expect(s.current(on: day(1)) == 1)
        s.mark(on: day(1))
        #expect(s.current(on: day(1)) == 2)
        // A day already lit takes no mark.
        s.mark(on: day(0))
        #expect(s.mine.isEmpty)
    }

    @Test func theRoomsStreakTellsThisPhonesMarksFromThePartners() {
        let wire = PairStreak(
            days: 4, best: 9, lastDay: "2026-11-04", restoredOn: nil,
            marks: [StreakMark(user: UserId("me"), day: "2026-11-05")])
        let mine = LoveStreak(wire, you: "me", calendar: cal)
        #expect(mine.count == 4)
        #expect(mine.lastDay == cal.startOfDay(for: day(0)))
        #expect(mine.turn(on: day(1), calendar: cal) == .partners)
        #expect(LoveStreak(wire, you: "partner", calendar: cal).turn(on: day(1), calendar: cal) == .yours)
        #expect(LoveStreak(wire, you: nil, calendar: cal).turn(on: day(1), calendar: cal) == nil)
    }

    @Test func aStreakSavedBeforeMarksStillReads() throws {
        let old = #"{"count":3,"best":5,"lastDay":0}"#
        let s = try JSONDecoder().decode(LoveStreak.self, from: Data(old.utf8))
        #expect(s.count == 3 && s.best == 5 && s.mine.isEmpty && s.partner.isEmpty)
    }

    @Test func aPushedStreakKeepsThisPhonesUnsentDaysOnTop() {
        var room = LoveStreak()
        room.record(on: day(0))
        room.partnerMark(on: day(1))
        let merged = StreakStore.merged(room, unsent: [day(1)])
        #expect(merged.count == 2)
        #expect(merged.status(on: day(1)) == .done)
    }
}

extension LoveStreak {
    /// The partner's part, as the room counts it.
    mutating func partnerMark(on date: Date) {
        swap(&mine, &partner)
        mark(on: date)
        swap(&mine, &partner)
    }
}

/// The pair's room, counting one streak for the couple with `LoveStreak`'s own rules.
@MainActor
private final class FakeStreakRoom {
    var shared = LoveStreak()
    var online = true
    var restorable = true
    private(set) var days: [Date] = []

    var remote: StreakRemote {
        StreakRemote(
            load: { @MainActor [self] in online ? .streak(shared) : .offline },
            record: { @MainActor [self] at in
                guard online else { return .offline }
                days.append(at)
                shared.mark(on: at)
                return .streak(shared)
            },
            restore: { @MainActor [self] in
                guard online else { return .offline }
                guard restorable, shared.status(on: day(6)) == .restorable else { return .refused }
                shared.restore(on: day(6))
                return .streak(shared)
            })
    }
}

@MainActor
@Suite struct SharedStreakTests {
    private let file = "Tests/\(UUID().uuidString)-streak.json"

    /// Lets the store's own sends run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func aDayHereWaitsForThePartnersInThePairsRoom() async {
        let room = FakeStreakRoom()
        let store = StreakStore(file: file)
        await store.follow(room.remote)

        store.record(at: day(0))
        await settle()
        #expect(room.days == [day(0)])
        #expect(store.streak.current(on: day(0)) == 0)
        #expect(store.streak.turn(on: day(0)) == .partners)
        // The same day again is nothing new to send.
        store.record(at: day(0).addingTimeInterval(60))
        #expect(store.unsent.isEmpty)

        room.shared.partnerMark(on: day(0))
        await store.refresh()
        #expect(store.streak.status(on: day(0)) == .done)

        // The partner went first the next day: it's this phone's turn, and its day lights it.
        room.shared.partnerMark(on: day(1))
        await store.refresh()
        #expect(store.streak.turn(on: day(1)) == .yours)
        store.record(at: day(1))
        await settle()
        #expect(store.streak.current(on: day(1)) == 2)
        #expect(store.streak.status(on: day(1)) == .done)
    }

    @Test func thePartnersDayPushedOverTheSocketShowsAtOnceWithTheDaysStillWaitingOnTop() async {
        let room = FakeStreakRoom()
        room.shared.record(on: day(0))
        let store = StreakStore(file: file)
        await store.follow(room.remote)
        room.online = false
        store.record(at: day(2))

        var pushed = room.shared
        pushed.record(on: day(1))
        pushed.partnerMark(on: day(2))
        store.received(pushed)
        #expect(store.streak.count == 3)
        #expect(store.streak.lastDay == cal.startOfDay(for: day(2)))
        #expect(store.unsent == [day(2)])
    }

    @Test func aPushBeforePairingLeavesThisPhonesOwnStreak() async {
        let store = StreakStore(file: file)
        await store.follow(nil)
        store.record(at: day(0))
        var pushed = LoveStreak()
        for d in 0..<5 { pushed.record(on: day(d)) }
        store.received(pushed)
        #expect(store.streak.count == 1)
    }

    @Test func aDayOfflineCountsHereAndGoesWhenTheRoomIsBack() async {
        let room = FakeStreakRoom()
        room.shared.record(on: day(0))
        let store = StreakStore(file: file)
        await store.follow(room.remote)
        room.online = false

        store.record(at: day(1))
        await settle()
        await store.refresh()
        #expect(store.unsent == [day(1)])
        #expect(store.streak.turn(on: day(1)) == .partners)
        // Kept across a launch.
        #expect(StreakStore(file: file).unsent == [day(1)])

        room.online = true
        room.shared.partnerMark(on: day(1))
        await store.refresh()
        #expect(room.days == [day(1)])
        #expect(store.unsent.isEmpty)
        #expect(room.shared.current(on: day(1)) == 2)
        #expect(store.streak == room.shared)
    }

    @Test func aRestoreIsThePairs() async {
        let room = FakeStreakRoom()
        for d in 0..<5 { room.shared.record(on: day(d)) }
        let store = StreakStore(file: file)
        await store.follow(room.remote)

        #expect(await store.restore())
        #expect(store.streak.lastRestore == room.shared.lastRestore)
        #expect(store.streak.status(on: day(6)) == .atRisk)

        room.restorable = false
        #expect(await store.restore() == false)
        room.online = false
        #expect(await store.restore() == false)
    }

    @Test func unpairedTheStreakStaysOnThisPhone() async {
        let store = StreakStore(file: file)
        await store.follow(nil)
        for d in 0..<5 { store.record(at: day(d)) }
        #expect(store.unsent.isEmpty)
        #expect(await store.restore(on: day(6)))
        #expect(store.streak.lastRestore == cal.startOfDay(for: day(6)))
    }
}
