import DesignSystem
import Foundation
import Testing

@testable import Labs

@Suite struct LampColourTests {
  @Test func theFiveColoursAreAllDifferent() {
    #expect(LampColour.allCases.count == 5)
    #expect(Set(LampColour.allCases.map(\.swatch)).count == 5)
    #expect(Set(LampColour.allCases.map(\.spokenName)).count == 5)
  }

  @Test(arguments: LampColour.allCases)
  func everyColourShowsAgainstTheNightPage(_ colour: LampColour) {
    #expect(Contrast.ratio(colour.swatch, Palette.pageDeep) >= ContrastFloor.mark.rawValue)
  }

  @MainActor @Test func aChosenColourIsKeptAcrossLaunches() {
    let defaults = UserDefaults(suiteName: "lamp-\(UUID().uuidString)") ?? .standard
    let store = LampStore(defaults: defaults)
    #expect(store.mine == .standard)
    store.choose(.green)
    #expect(LampStore(defaults: defaults).mine == .green)
  }

  @MainActor @Test func anUnknownStoredColourFallsBackToTheStandardOne() {
    let defaults = UserDefaults(suiteName: "lamp-\(UUID().uuidString)") ?? .standard
    defaults.set("purple-of-the-future", forKey: "labs.lampColour")
    #expect(LampStore(defaults: defaults).mine == .standard)
  }

  @MainActor @Test func thePartnersColourIsOnlyKnownOnceTheyShowIt() {
    let store = LampStore(
      defaults: UserDefaults(suiteName: "lamp-\(UUID().uuidString)") ?? .standard)
    #expect(store.theirs == nil)
    store.partnerGlows(PartnerGlow(colour: .rose))
    #expect(store.theirs?.colour == .rose)
  }
}
