import Foundation
import Testing

@testable import Pet

@Suite("TreatLedger")
struct TreatLedgerTests {
  private let me = "me"
  private let you = "you"

  private func calendar(_ zone: String = "Europe/Warsaw") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
  }

  private func ledger(_ days: [String: [String]]) -> TreatLedger {
    TreatLedger(days: days.mapValues(Set.init))
  }

  @Test func fedOnlyWhenBothGave() {
    #expect(ledger([:]).status(for: me, on: "2026-11-01") == .neither)
    #expect(ledger(["2026-11-01": [me]]).status(for: me, on: "2026-11-01") == .waitingOnPartner)
    #expect(ledger(["2026-11-01": [you]]).status(for: me, on: "2026-11-01") == .waitingOnMe)
    #expect(ledger(["2026-11-01": [me, you]]).status(for: me, on: "2026-11-01") == .fed)
  }

  @Test func yesterdaysTreatDoesNotCountToday() {
    #expect(ledger(["2026-10-31": [me, you]]).status(for: me, on: "2026-11-01") == .neither)
  }

  @Test func givingTwiceInADayChangesNothing() {
    var table = TreatLedger()
    table.give(device: me, on: "2026-11-01")
    table.give(device: me, on: "2026-11-01")
    #expect(table.status(for: me, on: "2026-11-01") == .waitingOnPartner)
  }

  @Test func streakCountsConsecutiveSharedDays() {
    let run = ledger([
      "2026-10-30": [me, you], "2026-10-31": [me, you], "2026-11-01": [me, you],
    ])
    #expect(run.streak(today: "2026-11-01", calendar: calendar()) == 3)
  }

  @Test func streakHoldsWhileTodayIsStillOpen() {
    let run = ledger(["2026-10-30": [me, you], "2026-10-31": [me, you], "2026-11-01": [me]])
    #expect(run.streak(today: "2026-11-01", calendar: calendar()) == 2)
  }

  @Test func aMissedDayResetsToZero() {
    let run = ledger(["2026-10-29": [me, you], "2026-10-30": [me, you], "2026-10-31": [me]])
    #expect(run.streak(today: "2026-11-01", calendar: calendar()) == 0)
  }

  @Test func aSingleSidedDayBreaksTheRun() {
    let run = ledger(["2026-10-29": [me, you], "2026-10-30": [me], "2026-10-31": [me, you]])
    #expect(run.streak(today: "2026-10-31", calendar: calendar()) == 1)
  }

  @Test func streakCrossesMonthAndYearEnds() {
    let run = ledger(["2026-12-31": [me, you], "2027-01-01": [me, you]])
    #expect(run.streak(today: "2027-01-01", calendar: calendar()) == 2)
  }

  @Test func streakSurvivesTheDayRollingOver() {
    let run = ledger(["2026-10-31": [me, you]])
    let calendar = calendar()
    #expect(run.streak(today: "2026-10-31", calendar: calendar) == 1)
    #expect(run.streak(today: "2026-11-01", calendar: calendar) == 1)
    #expect(run.streak(today: "2026-11-02", calendar: calendar) == 0)
  }

  @Test func dayKeyFollowsTheDevicesOwnCalendar() {
    // 23:30 on 1 Nov in Warsaw (UTC+1) is 22:30 UTC, and 10:30 on 1 Nov in Los Angeles.
    let instant = Date(timeIntervalSince1970: 1_793_572_200)
    #expect(TreatDay.key(for: instant, calendar: calendar("Europe/Warsaw")) == "2026-11-01")
    #expect(TreatDay.key(for: instant, calendar: calendar("Pacific/Auckland")) == "2026-11-02")
  }

  @Test func timestampCarriesTheLocalDayAndOffset() {
    let instant = Date(timeIntervalSince1970: 1_793_572_200)
    let stamp = TreatDay.timestamp(for: instant, calendar: calendar("Europe/Warsaw"))
    #expect(stamp == "2026-11-01T23:30:00+01:00")
    #expect(stamp.prefix(10) == "2026-11-01")
  }

  @Test func mergeKeepsAnUnacknowledgedLocalTreat() {
    var local = ledger(["2026-11-01": [me]])
    local.merge([:])
    #expect(local.status(for: me, on: "2026-11-01") == .waitingOnPartner)
    local.merge(["2026-11-01": [you]])
    #expect(local.status(for: me, on: "2026-11-01") == .fed)
  }

  @Test func reconnectWithTheRoomsTableRestoresAgreement() {
    var mine = PairPlay(device: me)
    var theirs = PairPlay(device: you)
    _ = mine.treatGiven(on: "2026-11-01")
    _ = theirs.treatGiven(on: "2026-11-01")
    let room = ["2026-11-01": Set([me, you])]
    var rebuilt = PairPlay(device: me)
    rebuilt.treatsReceived(room)
    #expect(rebuilt.status(on: "2026-11-01") == .fed)
    #expect(rebuilt.streak(today: "2026-11-01", calendar: calendar()) == 1)
  }

  @Test func onlyOneTreatPerDayPerDevice() {
    var play = PairPlay(device: me)
    let first = play.treatGiven(on: "2026-11-01")
    let repeated = play.treatGiven(on: "2026-11-01")
    let nextDay = play.treatGiven(on: "2026-11-02")
    #expect(first)
    #expect(!repeated)
    #expect(nextDay)
  }

  @Test func petsCountUpForEachSide() {
    var play = PairPlay(device: me)
    play.petGiven()
    play.petReceived()
    play.petReceived()
    #expect(play.petsGiven == 1)
    #expect(play.petsReceived == 2)
  }
}
