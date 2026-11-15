import Testing
@testable import Billet

struct CatTailTests {
    @Test func lyingTailCurvesWithoutAKink() {
        for posture in [CatWalker.Posture.sit, .loaf] {
            let bends = posture.tailBends
            #expect(bends.allSatisfy { $0 < 1.2 })
            for (a, b) in zip(bends, bends.dropFirst()) { #expect(abs(a - b) < 0.35) }
        }
    }

    @Test func theLoafTailIsNotLiftedAtTheTip() {
        #expect(CatWalker.Posture.tipLiftShare(lift: CatWalker.Posture.loaf.lift) == 0)
        for lift: Float in [CatWalker.Posture.sit.lift, 0, -0.032, 0.035] {
            #expect(CatWalker.Posture.tipLiftShare(lift: lift) == 1)
        }
    }
}
