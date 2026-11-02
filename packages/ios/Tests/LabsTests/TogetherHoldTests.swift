import Foundation
import Testing

@testable import Labs

@Suite struct TogetherHoldTests {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)
  private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

  @Test func oneFingerAloneNeverGetsAnywhere() {
    var hold = TogetherHold()
    hold.iHold(true, at: at(0))
    #expect(hold.progress(at: at(30)) == 0)
    #expect(!hold.isTogether(at: at(30)))
  }

  @Test func onlyTheTimeBothAreDownCounts() {
    var hold = TogetherHold()
    hold.iHold(true, at: at(0))
    hold.partnerHolds(true, at: at(5))
    #expect(abs(hold.overlap(at: at(5.6)) - 0.6) < 1e-3)
    #expect(abs(hold.progress(at: at(5.6)) - 0.5) < 1e-3)
  }

  @Test func theWispsMeetAfterTheNeededTime() {
    var hold = TogetherHold()
    hold.partnerHolds(true, at: at(0))
    hold.iHold(true, at: at(1))
    #expect(!hold.isTogether(at: at(1 + TogetherHold.needed - 0.01)))
    #expect(hold.isTogether(at: at(1 + TogetherHold.needed)))
    #expect(hold.progress(at: at(100)) == 1)
  }

  @Test func lettingGoStartsItOver() {
    var hold = TogetherHold()
    hold.iHold(true, at: at(0))
    hold.partnerHolds(true, at: at(0))
    hold.iHold(false, at: at(0.5))
    #expect(hold.progress(at: at(2)) == 0)
    hold.iHold(true, at: at(2))
    #expect(abs(hold.overlap(at: at(2.5)) - 0.5) < 1e-3)
  }

  @Test func holdingAgainWhileDownDoesNotRestartTheClock() {
    var hold = TogetherHold()
    hold.iHold(true, at: at(0))
    hold.iHold(true, at: at(3))
    #expect(hold.mine == at(0))
  }

  @Test func thePartnerLettingGoStopsIt() {
    var hold = TogetherHold()
    hold.iHold(true, at: at(0))
    hold.partnerHolds(true, at: at(0))
    hold.partnerHolds(false, at: at(1))
    #expect(!hold.partnerIsHolding)
    #expect(hold.progress(at: at(2)) == 0)
  }

  @Test func aClockBeforeBothHoldsGivesNothing() {
    var hold = TogetherHold()
    hold.iHold(true, at: at(10))
    hold.partnerHolds(true, at: at(10))
    #expect(hold.overlap(at: at(9)) == 0)
  }
}
