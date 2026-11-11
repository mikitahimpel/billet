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
}
