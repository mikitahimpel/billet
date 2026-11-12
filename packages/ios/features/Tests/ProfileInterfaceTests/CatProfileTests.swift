import Foundation
import Pet
import ProfileInterface
import Testing

@Suite struct CatProfileTests {
  func defaults() -> UserDefaults {
    let suite = "CatProfileTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }

  @Test func untilChosenTheCatIsTheyAndNothingIsChosen() {
    let defaults = defaults()
    #expect(CatProfile.chosenPronouns(in: defaults) == nil)
    #expect(CatProfile.pronouns(in: defaults) == .they)
  }

  @Test func aChoiceIsKeptAndCanBeTakenBack() {
    let defaults = defaults()
    for choice in CatPronouns.allCases {
      CatProfile.setPronouns(choice, in: defaults)
      #expect(CatProfile.chosenPronouns(in: defaults) == choice)
      #expect(CatProfile.pronouns(in: defaults) == choice)
    }
    CatProfile.setPronouns(nil, in: defaults)
    #expect(CatProfile.chosenPronouns(in: defaults) == nil)
  }

  @Test func anUnknownSavedValueCountsAsNotChosen() {
    let defaults = defaults()
    defaults.set("it", forKey: CatProfile.pronounsKey)
    #expect(CatProfile.chosenPronouns(in: defaults) == nil)
    #expect(CatProfile.pronouns(in: defaults) == .they)
  }
}
