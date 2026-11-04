import Foundation
import Testing

@testable import Pet

@Suite struct DailyStreakTests {
  private let calendar = Calendar(identifier: .gregorian)

  @Test func aDayBothDrewCountsLikeASharedTreat() {
    var ledger = TreatLedger()
    ledger.give(device: "a", on: "2026-11-02")
    ledger.give(device: "b", on: "2026-11-02")
    let drawn: Set<String> = ["2026-11-03", "2026-11-04"]
    #expect(ledger.streak(today: "2026-11-04", calendar: calendar) == 0)
    #expect(
      ledger.streak(today: "2026-11-04", calendar: calendar, paused: [], alsoShared: drawn) == 3)
  }

  @Test func aDayCountedBothWaysCountsOnce() {
    var ledger = TreatLedger()
    ledger.give(device: "a", on: "2026-11-04")
    ledger.give(device: "b", on: "2026-11-04")
    #expect(
      ledger.streak(
        today: "2026-11-04", calendar: calendar, paused: [], alsoShared: ["2026-11-04"]) == 1)
  }

  @Test func todayStaysOpenUntilBothHaveDrawn() {
    let ledger = TreatLedger()
    #expect(
      ledger.streak(
        today: "2026-11-04", calendar: calendar, paused: [],
        alsoShared: ["2026-11-02", "2026-11-03"]) == 2)
  }
}
