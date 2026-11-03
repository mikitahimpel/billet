import Foundation
import PetScene
import Testing

@testable import FeatureHome

@Suite struct OnboardingIntroTests {
  @Test func theFirstTimeItFliesThenTitlesThenRests() {
    var intro = OnboardingIntro(seenBefore: false)
    #expect(intro.step == .flying)
    #expect(intro.scene.moment == .arriving)
    #expect(!intro.showsTitle && !intro.showsActions && intro.canSkip)

    intro.send(.titleDue)
    #expect(intro.step == .titled)
    #expect(intro.showsTitle && !intro.showsActions)
    #expect(intro.scene.moment == .arriving)

    intro.send(.arrived)
    #expect(intro.step == .ready)
    #expect(intro.showsTitle && intro.showsActions && !intro.canSkip)
    #expect(intro.scene.moment == .resting)
  }

  @Test(arguments: [OnboardingIntro.Event.skipped, .arrived])
  func aTapOrAnEarlyArrivalBringsTheButtonsAtOnce(_ event: OnboardingIntro.Event) {
    var intro = OnboardingIntro(seenBefore: false)
    intro.send(event)
    #expect(intro.step == .ready)
    #expect(intro.showsTitle)
    #expect(intro.scene.moment == .resting)
  }

  @Test func onceSeenItOpensAtRest() {
    let intro = OnboardingIntro(seenBefore: true)
    #expect(intro.step == .ready)
    #expect(intro.scene.moment == .resting)
    #expect(!intro.canSkip)
  }

  @Test func nothingLateUndoesTheRest() {
    var intro = OnboardingIntro(seenBefore: false)
    intro.send(.skipped)
    for event in [OnboardingIntro.Event.titleDue, .arrived, .skipped] {
      intro.send(event)
      #expect(intro.step == .ready)
    }
  }

  @Test func theFlightIsRememberedOnThisPhone() throws {
    let defaults = try #require(UserDefaults(suiteName: "onboarding-\(UUID().uuidString)"))
    let memory = OnboardingMemory(defaults: defaults)
    #expect(!memory.introSeen)
    memory.rememberIntro()
    #expect(OnboardingMemory(defaults: defaults).introSeen)
  }
}
