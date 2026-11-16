import Foundation
import ProfileInterface
import Testing

/// With no partner on the server there are no days together, whatever `togetherSince` holds.
@Suite struct CoupleDaysTests {
  private let start = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
  private var fourDaysOn: Date { Calendar.current.date(byAdding: .day, value: 3, to: start)! }

  private func couple(paired: Bool) -> Couple {
    Couple(
      partners: ["L", "M"], togetherSince: start, viewer: "L",
      pair: paired ? PairMembers(pairID: "p", users: ["L": "u1", "M": "u2"]) : nil)
  }

  @Test func anUnpairedCoupleHasNoDaysTogether() {
    let alone = couple(paired: false)
    #expect(alone.daysTogether(on: fourDaysOn) == nil)
    #expect(alone.pairedSince == nil)
    #expect(alone.togetherSince == start)
    #expect(Couple.starter().daysTogether() == nil)
  }

  @Test func aPairedCoupleCountsTheFirstDayAsOne() {
    let paired = couple(paired: true)
    #expect(paired.daysTogether(on: start) == 1)
    #expect(paired.daysTogether(on: fourDaysOn) == 4)
    #expect(paired.pairedSince == start)
  }

  @Test func theLineWaitsForThePartnerUntilPaired() {
    #expect(
      Couple.dayLine(couple(paired: false).daysTogether(on: fourDaysOn))
        == "Waiting for your partner")
    #expect(Couple.dayLine(couple(paired: true).daysTogether(on: fourDaysOn)) == "Day 4 together")
  }
}
