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

  @MainActor
  @Test func theFlightIsRememberedOnlyForThisLaunch() {
    let memory = OnboardingMemory()
    #expect(!memory.introSeen)
    memory.rememberIntro()
    #expect(memory.introSeen)
    // A new run of the app starts with a fresh memory and flies in again.
    #expect(!OnboardingMemory().introSeen)
  }
}
