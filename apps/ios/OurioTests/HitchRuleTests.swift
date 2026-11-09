import Testing
@testable import Billet

@Suite struct HitchRuleTests {
    /// Frames at 60 Hz from `from` to `to` seconds, with extra gaps (seconds) ending at the given times.
    private func frames(_ from: Double, _ to: Double, late: [(gap: Double, at: Double)] = []) -> [ProbeFrame] {
        var all: [ProbeFrame] = []
        var at = from
        while at < to {
            if let stall = late.first(where: { abs($0.at - (at + 1.0 / 60)) < 0.5 / 60 }) {
                all.append(ProbeFrame(gap: stall.gap, at: stall.at))
                at = stall.at
            } else {
                at += 1.0 / 60
                all.append(ProbeFrame(gap: 1.0 / 60, at: at))
            }
        }
        return all
    }

    @Test func steadyFramesAreNeverLate() {
        #expect(HitchRule.late(frames(0, 3), from: 0.5).isEmpty)
    }

    @Test func oneDroppedFrameIsNotAHitchTwoAre() {
        #expect(HitchRule.late([ProbeFrame(gap: 2.0 / 60, at: 1)], from: 0.5).isEmpty)
        #expect(HitchRule.late([ProbeFrame(gap: 3.0 / 60, at: 1)], from: 0.5).count == 1)
    }

    @Test func aStallAfterTheStartCounts() {
        let late = HitchRule.late(frames(0, 3, late: [(0.27, 2)]), from: 1)
        #expect(late == [ProbeFrame(gap: 0.27, at: 2)])
    }

    @Test func aStallThatBeganBeforeTheStartIsTheHarnesss() {
        // XCUITest's launch handling on CI: a 274 ms frame ending at 0.98 s, the signal at 1 s.
        #expect(HitchRule.late([ProbeFrame(gap: 0.274, at: 0.98), ProbeFrame(gap: 0.016, at: 0.996)], from: 0.9).isEmpty)
        #expect(HitchRule.late([ProbeFrame(gap: 0.274, at: 1.2)], from: 1).isEmpty)
        #expect(HitchRule.late([ProbeFrame(gap: 0.274, at: 1.3)], from: 1).count == 1)
    }

    @Test func onlyFramesAfterTheStartAreCounted() {
        #expect(HitchRule.counted(frames(0, 3), from: 1) > 110)
        #expect(HitchRule.counted(frames(0, 3), from: .infinity) == 0, "no signal, nothing measured")
    }

    @Test func runnerNoiseIsNotJank() {
        // main on 8ecad628: three late frames of 41-66 ms.
        let late = [
            ProbeFrame(gap: 0.066, at: 2.145), ProbeFrame(gap: 0.041, at: 2.25), ProbeFrame(gap: 0.041, at: 2.295),
        ]
        #expect(!HitchRule.janks(late))
        #expect(!HitchRule.janks([]))
    }

    @Test func aStallIsJank() {
        #expect(HitchRule.janks([ProbeFrame(gap: 0.101, at: 2)]))
        #expect(!HitchRule.janks([ProbeFrame(gap: 0.1, at: 2)]))
    }

    @Test func manyLateFramesAreJank() {
        let frame = ProbeFrame(gap: 0.05, at: 2)
        #expect(!HitchRule.janks(Array(repeating: frame, count: HitchRule.lateBudget)))
        #expect(HitchRule.janks(Array(repeating: frame, count: HitchRule.lateBudget + 1)))
    }
}
