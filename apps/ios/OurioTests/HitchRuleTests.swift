import Testing
@testable import Billet

@Suite struct HitchRuleTests {
    private let hz60 = Array(repeating: 1.0 / 60, count: 100)
    private let hz120 = Array(repeating: 1.0 / 120, count: 100)
    /// A Simulator without a GPU on CI: about 25 frames a second, unevenly.
    private let slow = (0..<80).map { 0.036 + Double($0 % 5) * 0.002 }

    @Test func steadyFramesAreNeverLate() {
        #expect(HitchRule.late(hz60).isEmpty)
        #expect(HitchRule.late(hz120).isEmpty)
        #expect(HitchRule.late(slow).isEmpty)
    }

    @Test func oneDroppedFrameIsNotAHitchTwoAre() {
        #expect(HitchRule.late(hz60 + [2.0 / 60]).isEmpty)
        #expect(HitchRule.late(hz60 + [3.0 / 60]) == [100])
    }

    @Test func fastDisplaysKeepTheSixtyHertzLimit() {
        #expect(HitchRule.limit(hz120) == HitchRule.floor)
        #expect(HitchRule.late(hz120 + [0.03]).isEmpty)
        #expect(HitchRule.late(hz120 + [0.04]) == [100])
    }

    @Test func aSlowDisplayIsJudgedByItsOwnFrames() {
        let cadence = HitchRule.cadence(slow)
        #expect(cadence > 0.035 && cadence < 0.045)
        #expect(HitchRule.late(slow + [cadence * 2]).isEmpty)
        #expect(HitchRule.late(slow + [cadence * 3]) == [80])
        #expect(HitchRule.late(slow + [0.25]) == [80], "a stall is late at any rate")
    }

    @Test func aStallIsLateHoweverSlowTheDisplay() {
        let crawl = Array(repeating: 0.09, count: 40)
        #expect(HitchRule.limit(crawl) == HitchRule.ceiling)
        #expect(HitchRule.late(crawl + [0.12]) == [40])
    }

    @Test func noFramesNoHitches() {
        #expect(HitchRule.late([]).isEmpty)
        #expect(HitchRule.cadence([]) == 0)
    }
}
