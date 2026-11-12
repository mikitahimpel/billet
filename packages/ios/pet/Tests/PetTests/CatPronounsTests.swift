import Foundation
import Testing

@testable import Pet

@Suite struct CatPronounsTests {
  static let phrases: [CatPhrase] = [
    .napsOnOwn, .tapToPet, .ringExplained, .portraitTreats(price: 25),
    .needsSettlingIn(name: "Tofu"), .dayStarting, .aboutHeading, .opensNeeds, .doubleTapToPet,
    .bowlCapped, .tooMuchWarning, .tooMuchResult, .widgetBlurb, .widgetShowcaseState,
    .widgetShowcaseMood, .brainFooter(name: "Tofu"), .brushGoal, .bedSpot, .boxSpot,
  ]

  private static func words(_ text: String) -> Set<String> {
    Set(
      text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init))
  }

  static let feminine: Set<String> = ["she", "she's", "she'll", "her", "hers", "herself"]
  static let masculine: Set<String> = ["he", "he's", "he'll", "his", "him", "himself"]
  static let neutral: Set<String> = [
    "they", "they're", "they'll", "their", "theirs", "them", "themself", "themselves",
  ]

  @Test(arguments: phrases) func everyPhraseRendersForEveryChoice(phrase: CatPhrase) {
    for pronouns in CatPronouns.allCases {
      #expect(!pronouns.say(phrase).isEmpty)
    }
    let texts = Set(CatPronouns.allCases.map { $0.say(phrase) })
    #expect(texts.count == 3)
  }

  @Test(arguments: phrases) func aChoiceNeverLeaksAnotherFormsWords(phrase: CatPhrase) {
    let she = Self.words(CatPronouns.she.say(phrase))
    let he = Self.words(CatPronouns.he.say(phrase))
    let they = Self.words(CatPronouns.they.say(phrase))
    #expect(she.isDisjoint(with: Self.masculine.union(Self.neutral)))
    #expect(he.isDisjoint(with: Self.feminine.union(Self.neutral)))
    #expect(they.isDisjoint(with: Self.feminine.union(Self.masculine)))
    #expect(!she.isDisjoint(with: Self.feminine))
    #expect(!he.isDisjoint(with: Self.masculine))
    #expect(!they.isDisjoint(with: Self.neutral))
  }

  @Test func theNameAndPriceSurviveInEveryChoice() {
    for pronouns in CatPronouns.allCases {
      #expect(pronouns.say(.needsSettlingIn(name: "Tofu")).hasPrefix("Tofu is settling in."))
      #expect(pronouns.say(.brainFooter(name: "Biscuit")).contains("Biscuit lives on"))
      #expect(pronouns.say(.portraitTreats(price: 25)).contains("for 25 coins"))
    }
  }

  @Test func theVerbMovesWithThePronoun() {
    #expect(CatPronouns.she.say(.widgetBlurb).contains("she is"))
    #expect(CatPronouns.they.say(.widgetBlurb).contains("they are"))
    #expect(CatPronouns.they.say(.tooMuchResult) == "Too much! They're stuffed")
    #expect(CatPronouns.he.say(.tooMuchWarning) == "Too much! He'll be stuffed")
    #expect(CatPronouns.they.say(.dayStarting).contains("What they get up to"))
  }

  @Test func untilChosenTheCatIsTheyAndTheRawValuesAreTheWireOnes() {
    #expect(CatPronouns.unchosen == .they)
    #expect(CatPronouns.allCases.map(\.rawValue) == ["she", "he", "they"])
    #expect(CatPronouns(rawValue: "it") == nil)
    #expect(CatPronouns.allCases.map(\.label) == ["She / her", "He / him", "They / them"])
  }
}
