import Testing
@testable import Billet

struct CatPaceTests {
    @Test func theEagerPaceIsQuickerInEveryMove() {
        let usual = CatPace.usual, eager = CatPace.eager
        #expect(eager.walkSpeed > usual.walkSpeed)
        #expect(eager.rampTime < usual.rampTime)
        #expect(eager.turnRate > usual.turnRate)
        #expect(eager.standUp < usual.standUp)
        #expect(eager.sitDown < usual.sitDown)
        #expect(eager.gather < usual.gather)
        #expect(eager.wiggle.upperBound < usual.wiggle.lowerBound)
        #expect(eager.poise < usual.poise)
        #expect(eager.flight < usual.flight)
    }

    @Test func theEagerPaceStillShowsHerGatheringForAJump() {
        // A pounce without its crouch and wiggle reads as a slide, and a leap too quick as a cut.
        let eager = CatPace.eager
        #expect(eager.gather + eager.wiggle.lowerBound + eager.poise >= 0.4)
        #expect(eager.flight >= 0.6)
        // Her gait's cycle quickens by a quarter at most (CatGait), so the paws keep up with the body.
        #expect(eager.walkSpeed / CatPace.usual.walkSpeed <= 1.5)
    }
}
