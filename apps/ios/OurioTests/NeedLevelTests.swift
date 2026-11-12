import Foundation
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

    @Test(arguments: [
        (2, 0.0, "34 pets to Lv. 3"), (2, 0.4, "20 pets to Lv. 3"), (5, 0.97, "One more pet to Lv. 6"),
        (1, 0.999, "One more pet to Lv. 2"), (1, 1.5, "One more pet to Lv. 2"), (1, -1.0, "34 pets to Lv. 2"),
        (1, Double.nan, "34 pets to Lv. 2"),
    ])
    func theWayToTheNextLevelIsCountedInPets(level: Int, progress: Double, words: String) {
        #expect(CatCare.towardNext(level: level, progress: progress) == words)
    }

    @Test func theRingRoundHerPortraitPutsEachNeedWhereItsTileIs() {
        // Clockwise from the upper leading quarter: the two upper tiles, then the lower trailing, then the lower leading.
        let grid = PetNeed.displayOrder
        #expect(PetNeed.ringOrder == [grid[0], grid[1], grid[3], grid[2]])
    }

    @Test func herPortraitSpeaksAllFourLevels() {
        #expect(PetButton.spoken(PetNeeds(full: 0.2, rested: 0.9, loved: 0.5, playful: 0.75))
            == "Full 20 percent, Rested 90 percent, Playful 75 percent, Loved 50 percent")
    }

    @Test(arguments: CatDayMoment.Kind.allCases)
    func everyMomentOfHerDayHasAMarkAndAShortName(kind: CatDayMoment.Kind) {
        #expect(!kind.symbol.isEmpty)
        #expect(!kind.title.isEmpty && kind.title.count <= 10)
    }

    @Test func aMomentTellsItsTimeInTheZoneAsked() throws {
        let zone = try #require(TimeZone(secondsFromGMT: 3600))
        let british = Locale(identifier: "en_GB")
        let noon = 1_793_620_800.0
        let fed = CatDayMoment(kind: .ate, at: noon + 720, exact: true)
        let nap = CatDayMoment(kind: .napped, at: noon, until: noon + 7200, exact: false)
        let night = CatDayMoment(kind: .slept, at: noon - 8 * 3600, until: noon - 5 * 3600, exact: false)
        #expect(fed.time(in: zone, locale: british) == "13:12")
        #expect(nap.time(in: zone, locale: british) == "13:00")
        #expect(night.time(in: zone, locale: british) == "till 08:00")
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
        #expect((need.note(pronouns: .they) == nil) == (care != nil), "a need without care says why")
    }

    @Test func theCareUnderTheRowsIsNoNeedsOwn() {
        let ofNeeds = Set(PetNeed.allCases.compactMap(\.care))
        #expect(ofNeeds.isDisjoint(with: NeedCare.more))
        #expect(NeedCare.more.map(\.title) == ["Water", "Brush"])
    }

    @Test func beforeHerNeedsAreKnownEveryCareIsStillThere() {
        #expect(NeedCare.extra(needsKnown: true) == NeedCare.more)
        #expect(NeedCare.extra(needsKnown: false).map(\.title) == ["Feed", "Play", "Pet", "Water", "Brush"])
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
    func onlyTheLowestNeedIsRaisedAndOnlyWhileItWants(needs: PetNeeds, cue: PetNeed?) {
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
