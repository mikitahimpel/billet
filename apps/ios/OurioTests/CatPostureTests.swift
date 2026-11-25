import Testing
@testable import Billet

struct CatPostureTests {
    typealias Posture = CatWalker.Posture

    @Test func anOrderedChangeStartsAndEndsOnItsPostures() {
        for order in [Posture.Order.rising, .sitting] {
            let start = Posture.blend(.stand, .sit, 0, order)
            #expect(start.lift == Posture.stand.lift)
            #expect(start.pitch == Posture.stand.pitch)
            #expect(start.hind.y + start.hindSplit == SIMD2(repeating: Posture.stand.hind.y))
            let end = Posture.blend(.stand, .sit, 1, order)
            #expect(end.lift == Posture.sit.lift)
            #expect(end.pitch == Posture.sit.pitch)
            #expect(end.hind == Posture.sit.hind)
            #expect(end.hindSplit == .zero)
            #expect(end.tail == Posture.sit.tail)
        }
    }

    @Test func sittingDownTheHindPawsStepInOneAfterTheOtherBeforeTheRumpIsDown() {
        let early = Posture.blend(.stand, .sit, 0.25, .sitting)
        #expect(abs(early.hindSplit.x) > abs(early.hindSplit.y))
        #expect(abs(early.hindSplit.x) > 0.8 * abs(Posture.sit.hind.y))
        #expect(abs(early.lift) < 0.2 * abs(Posture.sit.lift))
    }

    @Test func gettingUpTheRumpIsUpBeforeTheTail() {
        let half = Posture.blend(.sit, .stand, 0.5, .rising)
        #expect(abs(half.lift - Posture.stand.lift) < 0.35 * abs(Posture.sit.lift))
        #expect(abs(half.tail[0] - Posture.stand.tail[0]) > 0.6 * abs(Posture.sit.tail[0]))
    }

    @Test func noPartMovesBackwardsDuringAChange() {
        for order in [Posture.Order.rising, .sitting] {
            var last = Posture.blend(.sit, .stand, 0, order)
            for step in 1...50 {
                let next = Posture.blend(.sit, .stand, Float(step) / 50, order)
                #expect(next.lift >= last.lift)
                #expect(next.pitch <= last.pitch)
                last = next
            }
        }
    }
}
