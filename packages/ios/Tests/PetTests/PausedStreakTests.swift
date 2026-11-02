import Foundation
import Testing

@testable import Pet

@Suite struct PausedStreakTests {
  private let calendar = Calendar(identifier: .gregorian)

  private func ledger(sharedOn days: [String]) -> TreatLedger {
    var ledger = TreatLedger()
    for day in days {
      ledger.give(device: "a", on: day)
      ledger.give(device: "b", on: day)
    }
    return ledger
  }

  @Test func withoutPausesItIsTheOrdinaryStreak() {
    let ledger = ledger(sharedOn: ["2026-11-01", "2026-11-02"])
    #expect(
      ledger.streak(today: "2026-11-02", calendar: calendar, paused: [])
        == ledger.streak(today: "2026-11-02", calendar: calendar))
  }

  @Test func aPausedDayDoesNotEndTheRun() {
    let ledger = ledger(sharedOn: ["2026-10-29", "2026-10-30", "2026-11-02"])
    #expect(ledger.streak(today: "2026-11-02", calendar: calendar) == 1)
    #expect(
      ledger.streak(today: "2026-11-02", calendar: calendar, paused: ["2026-10-31", "2026-11-01"])
        == 3)
  }

  @Test func aPausedDayAddsNothingToTheCount() {
    let ledger = ledger(sharedOn: ["2026-10-30"])
    #expect(
      ledger.streak(
        today: "2026-11-02", calendar: calendar, paused: ["2026-10-31", "2026-11-01", "2026-11-02"])
        == 1)
  }

  @Test func aDayThatIsNotPausedStillEndsTheRun() {
    let ledger = ledger(sharedOn: ["2026-10-29", "2026-10-30", "2026-11-02"])
    #expect(ledger.streak(today: "2026-11-02", calendar: calendar, paused: ["2026-11-01"]) == 1)
  }

  @Test func pausedDaysFarInThePastChangeNothing() {
    let ledger = ledger(sharedOn: ["2026-11-01"])
    #expect(ledger.streak(today: "2026-11-02", calendar: calendar, paused: ["2020-01-01"]) == 1)
  }
}
