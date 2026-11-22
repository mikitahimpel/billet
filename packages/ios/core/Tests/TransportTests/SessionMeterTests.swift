import Testing
import Wire

@testable import Transport

@Suite struct SessionMeterTests {
  private let start = ContinuousClock.now

  @Test func aLaunchIsOneOpenAndEachStayEndsOnce() {
    var meter = SessionMeter()
    #expect(meter.moved(to: .aside, at: start) == [])
    #expect(meter.moved(to: .front, at: start) == [ClientEvent(.appOpened)])
    #expect(meter.moved(to: .front, at: start + .seconds(5)) == [])
    #expect(
      meter.moved(to: .away, at: start + .seconds(30))
        == [ClientEvent(.sessionEnded, detail: "under-1m")])
    #expect(meter.moved(to: .away, at: start + .seconds(40)) == [])
    #expect(meter.moved(to: .front, at: start + .seconds(100)) == [])
    #expect(
      meter.moved(to: .away, at: start + .seconds(400))
        == [ClientEvent(.sessionEnded, detail: "from-3m")])
  }

  @Test func timeAsideCountsAndTimeAwayDoesNot() {
    var meter = SessionMeter()
    _ = meter.moved(to: .front, at: start)
    #expect(meter.moved(to: .aside, at: start + .seconds(50)) == [])
    #expect(meter.moved(to: .front, at: start + .seconds(70)) == [])
    #expect(
      meter.moved(to: .away, at: start + .seconds(90))
        == [ClientEvent(.sessionEnded, detail: "from-1m")])
    _ = meter.moved(to: .front, at: start + .seconds(5000))
    #expect(
      meter.moved(to: .away, at: start + .seconds(5010))
        == [ClientEvent(.sessionEnded, detail: "under-1m")])
  }

  @Test func leavingBeforeEverComingToTheFrontCountsNothing() {
    var meter = SessionMeter()
    #expect(meter.moved(to: .away, at: start) == [])
  }

  @Test(arguments: [
    (0, SessionLength.underOneMinute), (59, .underOneMinute), (60, .oneToThreeMinutes),
    (179, .oneToThreeMinutes), (180, .threeToTenMinutes), (599, .threeToTenMinutes),
    (600, .tenMinutesOrMore), (86_400, .tenMinutesOrMore),
  ])
  func aLengthIsOneOfFourRanges(seconds: Int, length: SessionLength) {
    #expect(SessionLength(.seconds(seconds)) == length)
  }

  @Test func everyLengthKeepsTheEventsRule() {
    for length in SessionLength.allCases {
      #expect(ClientEvent(.sessionEnded, detail: length.rawValue).problem == nil)
    }
    #expect(ClientEvent(.sessionEnded).problem != nil)
    #expect(ClientEvent(.sessionEnded, detail: "42s").problem != nil)
  }
}
