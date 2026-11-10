import GamesInterface
import Pet
import Testing
@testable import Billet

@Suite struct NeedLevelTests {
    @Test(arguments: [
        (1.0, NeedLevel.content), (0.7, .content), (0.69, .okay), (0.5, .okay), (0.35, .okay), (0.34, .wants),
        (0.2, .wants), (0.0, .wants),
    ])
    func aValueReadsAsOneLevel(value: Double, level: NeedLevel) {
        #expect(NeedLevel(value) == level)
    }

    @Test func theScreenAndTheBrainDrawTheSameLowLine() {
        #expect(NeedLevel.wantsBelow == LifeConfig.standard.lowBelow)
    }

    @Test(arguments: PetNeed.allCases)
    func everyLevelHasItsOwnShortWord(need: PetNeed) {
        let words = NeedLevel.allCases.map(need.word)
        #expect(Set(words).count == NeedLevel.allCases.count)
        #expect(words.allSatisfy { !$0.isEmpty && $0.count <= 14 && $0 != need.title })
    }

    @Test(arguments: [
        (PetNeed.full, "Well fed", "Peckish", "Hungry"),
        (.rested, "Wide awake", "Drowsy", "Sleepy"),
        (.playful, "Had fun", "Curious", "Wants to play"),
        (.loved, "Adored", "Cuddly", "Wants a cuddle"),
    ])
    func wordsPerNeed(need: PetNeed, content: String, okay: String, wants: String) {
        #expect(need.word(.content) == content)
        #expect(need.word(.okay) == okay)
        #expect(need.word(.wants) == wants)
    }

    @Test func voiceOverHearsTheWordAndTheNumber() {
        #expect(PetNeed.full.spoken(0.2) == "Hungry, 20 percent")
        #expect(PetNeed.loved.spoken(0.9) == "Adored, 90 percent")
    }

    @Test(arguments: [
        (PetNeed.full, NeedCare?.some(.game(.feed))), (.playful, .game(.laser)), (.loved, .pet), (.rested, nil),
    ])
    func eachNeedOpensItsCare(need: PetNeed, care: NeedCare?) {
        #expect(need.care == care)
        #expect((need.note == nil) == (care != nil), "a need without care says why")
    }

    @Test func theCareUnderTheRowsIsNoNeedsOwn() {
        let ofNeeds = Set(PetNeed.allCases.compactMap(\.care))
        #expect(ofNeeds.isDisjoint(with: NeedCare.more))
        #expect(NeedCare.more.map(\.title) == ["Water", "Brush"])
    }

    @Test(arguments: [
        (PetNeeds(all: 0.9), PetNeed?.none),
        (PetNeeds(all: 0.5), nil),
        (PetNeeds(all: 0.35), nil),
        (PetNeeds(full: 0.9, rested: 0.9, loved: 0.9, playful: 0.2), .playful),
        (PetNeeds(full: 0.3, rested: 0.9, loved: 0.1, playful: 0.2), .loved),
        (PetNeeds(full: 0.2, rested: 0.6, loved: 0.6, playful: 0.6), .full),
        (PetNeeds(all: 0.2), .full),
    ])
    func homeCuesTheLowestNeedOnlyWhileItWants(needs: PetNeeds, cue: PetNeed?) {
        #expect(NeedLevel.cue(needs) == cue)
    }

    @Test(arguments: [
        (PetNeeds(all: 0.9), "Happy and cosy"),
        (PetNeeds(full: 0.5, rested: 0.9, loved: 0.9, playful: 0.9), "Could nibble something"),
        (PetNeeds(full: 0.9, rested: 0.9, loved: 0.9, playful: 0.1), "Mochi would love to play"),
    ])
    func theMoodLineFollowsTheLowestNeed(needs: PetNeeds, line: String) {
        #expect(needs.moodLine(name: "Mochi") == line)
    }
}
