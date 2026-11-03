import Foundation
import Pet
import Testing

@testable import Labs

@MainActor
@Suite struct LifeViewsTests {
  @Test func aChipGlowsOnlyOnceTheNeedIsMet() {
    #expect(LifeChips.glow(0.2) == 0)
    #expect(LifeChips.glow(0.55) > 0.4 && LifeChips.glow(0.55) < 0.6)
    #expect(LifeChips.glow(0.9) == 1)
    #expect(LifeChips.word(0.2) == "low")
    #expect(LifeChips.word(0.9) == "good")
  }

  @Test func theBubbleShowsTheFocusAndNothingWhileAsleep() {
    #expect(LifeThought.need(LifeDrive(asleep: false, focus: .full)) == .full)
    #expect(LifeThought.need(LifeDrive(asleep: true, focus: .full)) == nil)
    #expect(LifeThought.need(LifeDrive()) == nil)
  }

  @Test func theRingsSpeakInWordsNotNumbers() {
    let spoken = LifeRings.spoken(PetNeeds(all: 0.9), name: "Mochi")
    #expect(spoken.hasPrefix("Mochi."))
    #expect(spoken.allSatisfy { !$0.isNumber })
  }
}
