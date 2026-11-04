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

  @Test func theCardPutsTheHungryCatsFoodFirstAndSaysSo() {
    let needs = PetNeeds(full: 0.1, rested: 0.3, loved: 0.9, playful: 0.5)
    let card = CatNeedsSnapshot(needs: needs, feeling: .hungry, name: "Mochi")
    #expect(card.ordered == [.full, .rested, .playful, .loved])
    #expect(card.line == "Mochi is hungry. A treat? 🐟")
    #expect(card.urgent == .full)
  }

  @Test func theFeelingsNeedLeadsEvenWhenAnotherIsLower() {
    let needs = PetNeeds(full: 0.6, rested: 0.1, loved: 0.2, playful: 0.6)
    let card = CatNeedsSnapshot(needs: needs, feeling: .lonely, name: "Mochi")
    #expect(card.ordered == [.loved, .rested, .full, .playful])
  }

  @Test func aContentCatKeepsTheUsualOrderOnTies() {
    let card = CatNeedsSnapshot(needs: PetNeeds(all: 0.8), feeling: .content, name: "Mochi")
    #expect(card.urgent == nil)
    #expect(card.ordered == [.full, .loved, .playful, .rested])
  }

  @Test func aHangryCatAsksForFoodNow() {
    let card = CatNeedsSnapshot(needs: PetNeeds(all: 0.05), feeling: .hangry, name: "Mochi")
    #expect(card.ordered.first == .full)
    #expect(card.line == "Mochi is hangry. Food, now! 😾")
  }

  @Test func aSleepingCatNeedsNoTuckingIn() {
    let card = CatNeedsSnapshot(needs: PetNeeds(all: 0.5), feeling: .asleep, name: "Mochi")
    #expect(!card.canAnswer(.rested))
    #expect(card.canAnswer(.full))
  }

  @Test func theCardSpeaksInWordsNotNumbers() {
    let card = CatNeedsSnapshot(needs: PetNeeds(all: 0.9), feeling: .happy, name: "Mochi")
    let spoken = CatNeedsCard.spoken(card)
    #expect(spoken.hasPrefix("Mochi is happy."))
    #expect(spoken.contains("Food: good"))
    #expect(spoken.allSatisfy { !$0.isNumber })
  }

  @Test func everyNeedHasAnAction() {
    #expect(PetNeed.allCases.map(\.action) == ["Feed", "Let it nap", "Pet", "Play"])
  }
}
