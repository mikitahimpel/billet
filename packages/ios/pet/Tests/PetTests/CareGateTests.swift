import Foundation
import Testing

@testable import Pet

struct CareGateTests {
  let t0 = Date(timeIntervalSince1970: 1_800_000_000)
  let hungry = PetNeeds(full: 0.4, rested: 0.7, loved: 0.4, playful: 0.4)

  @Test func aMetNeedRefusesItsCareWithoutRecordingIt() {
    var gate = CareGate()
    let full = PetNeeds(full: 1, rested: 0.7, loved: 0.4, playful: 0.4)
    #expect(gate.attempt(.feed, needs: full, now: t0) == .refused(.met, until: nil))
    #expect(gate.attempt(.treat, needs: full, now: t0) == .refused(.met, until: nil))
    #expect(gate.given.isEmpty)
    #expect(gate.attempt(.pet, needs: full, now: t0).isOpen)
  }

  @Test func eachCareReadsItsOwnNeed() {
    let gate = CareGate()
    let loved = PetNeeds(full: 0.3, rested: 0.3, loved: 0.95, playful: 0.3)
    #expect(gate.verdict(.pet, needs: loved, now: t0) == .refused(.met, until: nil))
    #expect(gate.verdict(.brush, needs: loved, now: t0) == .refused(.met, until: nil))
    #expect(gate.verdict(.feed, needs: loved, now: t0).isOpen)
    #expect(gate.verdict(.play, needs: loved, now: t0).isOpen)
    let played = PetNeeds(full: 0.3, rested: 0.3, loved: 0.3, playful: 1)
    #expect(gate.verdict(.play, needs: played, now: t0) == .refused(.met, until: nil))
    #expect(gate.verdict(.water, needs: PetNeeds(all: 1), now: t0).isOpen)
  }

  @Test func aRunOfPetsTiresHerAndTheRestLifts() {
    var gate = CareGate()
    for i in 0..<6 {
      #expect(gate.attempt(.pet, needs: hungry, now: t0.addingTimeInterval(Double(i) * 10)).isOpen)
    }
    let seventh = gate.attempt(.pet, needs: hungry, now: t0.addingTimeInterval(60))
    #expect(seventh == .refused(.tired, until: t0.addingTimeInterval(300)))
    #expect(gate.given[.pet]?.count == 6)
    #expect(gate.attempt(.pet, needs: hungry, now: t0.addingTimeInterval(301)).isOpen)
  }

  @Test func askingAgainWhileTiredDoesNotMoveTheRestAway() {
    var gate = CareGate()
    for i in 0..<3 { _ = gate.attempt(.play, needs: hungry, now: t0.addingTimeInterval(Double(i))) }
    let first = gate.attempt(.play, needs: hungry, now: t0.addingTimeInterval(100))
    for s in stride(from: 110.0, to: 600, by: 50) {
      _ = gate.attempt(.play, needs: hungry, now: t0.addingTimeInterval(s))
    }
    #expect(gate.attempt(.play, needs: hungry, now: t0.addingTimeInterval(700)) == first)
    #expect(gate.attempt(.play, needs: hungry, now: t0.addingTimeInterval(15 * 60)).isOpen)
  }

  @Test func careIsCountedPerKindAndPassesWithTime() {
    var gate = CareGate()
    for _ in 0..<2 { _ = gate.attempt(.water, needs: nil, now: t0) }
    #expect(!gate.verdict(.water, needs: nil, now: t0.addingTimeInterval(60)).isOpen)
    #expect(gate.verdict(.brush, needs: nil, now: t0.addingTimeInterval(60)).isOpen)
    #expect(gate.verdict(.water, needs: nil, now: t0.addingTimeInterval(31 * 60)).isOpen)
  }

  @Test func treatsRunOutAfterThreeAnHour() {
    var gate = CareGate()
    for i in 0..<3 {
      _ = gate.attempt(.treat, needs: hungry, now: t0.addingTimeInterval(Double(i) * 120))
    }
    #expect(
      gate.verdict(.treat, needs: hungry, now: t0.addingTimeInterval(600))
        == .refused(.tired, until: t0.addingTimeInterval(3600)))
  }

  @Test func unknownNeedsLeaveOnlyBurstsAndFutureClocksDoNotCount() {
    var gate = CareGate()
    #expect(gate.attempt(.feed, needs: nil, now: t0).isOpen)
    // An event stamped later than now (a clock set back) is not "recent".
    _ = gate.attempt(.water, needs: nil, now: t0.addingTimeInterval(1000))
    _ = gate.attempt(.water, needs: nil, now: t0.addingTimeInterval(1000))
    #expect(gate.verdict(.water, needs: nil, now: t0).isOpen)
  }

  @Test func theStandardLimitsCoverEveryCareThatHasABurst() {
    #expect(
      CareLimits.standard.bursts.keys.sorted { $0.rawValue < $1.rawValue }
        == [.brush, .pet, .play, .treat, .water])
    #expect(CareLimits.standard == CareLimits())
  }
}
