import Testing

@testable import FeatureSettings

@Suite struct AppIconChoiceTests {
  @Test func thePrimaryIconIsTheTwoCats() {
    #expect(AppIconChoice(alternateName: nil) == .twoCats)
    #expect(AppIconChoice.twoCats.alternateName == nil)
  }

  @Test func everyChoiceRoundTripsThroughItsIconName() {
    for choice in AppIconChoice.allCases {
      #expect(AppIconChoice(alternateName: choice.alternateName) == choice)
    }
  }

  @Test func anUnknownIconNameFallsBackToThePrimary() {
    #expect(AppIconChoice(alternateName: "AppIconGone") == .twoCats)
  }

  @Test func eachChoiceHasItsOwnIconAndThumbnail() {
    let names = AppIconChoice.allCases.map(\.alternateName)
    #expect(Set(names).count == names.count)
    #expect(Set(AppIconChoice.allCases.map(\.thumbnail)).count == AppIconChoice.allCases.count)
  }
}
