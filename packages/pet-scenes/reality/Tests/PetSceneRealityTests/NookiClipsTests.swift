import Foundation
import RealityKit
import Testing

@testable import PetSceneReality

@Suite struct NookiClipChoiceTests {
  @Test func eachClipSitsOnItsTrim() {
    #expect(NookiClip.idle.trim == 0...4)
    #expect(NookiClip.walk.trim == 4.333...5.333)
    #expect(NookiClip.sit.trim == 5.667...9.667)
    #expect(NookiClip.sleep.trim == 10...16)
    #expect(NookiClip.crouchWiggle.trim == 16.333...17.333)
    #expect(NookiClip.pounce.trim == 17.667...19.167)
  }

  @Test func onlyThePounceRunsOnce() {
    #expect(NookiClip.allCases.filter { !$0.loops } == [.pounce])
  }

  @Test func aSleepingMochiSleeps() {
    #expect(NookiClip.choose(frame: NookiFrame(), yarn: .resting) == .sleep)
  }

  @Test func anAwakeMochiIdlesAndAWalkingOneWalks() {
    let awake = NookiFrame(wake: 1, eyesOpen: true)
    #expect(NookiClip.choose(frame: awake, yarn: .resting) == .idle)
    var walking = awake
    walking.walk = 0.5
    #expect(NookiClip.choose(frame: walking, yarn: .resting) == .walk)
  }

  @Test func aSettlingMochiSitsBeforeSleeping() {
    let settling = NookiFrame(wake: 0.3, eyesOpen: true)
    #expect(NookiClip.choose(frame: settling, yarn: .resting) == .sit)
  }

  @Test func theGameHasItsOwnClips() {
    let frame = NookiFrame(wake: 1, eyesOpen: true)
    #expect(NookiClip.choose(frame: frame, yarn: .watching) == .sit)
    #expect(NookiClip.choose(frame: frame, yarn: .crouching) == .crouchWiggle)
    #expect(NookiClip.choose(frame: frame, yarn: .wiggling) == .crouchWiggle)
    #expect(NookiClip.choose(frame: frame, yarn: .chasing) == .walk)
    #expect(NookiClip.choose(frame: frame, yarn: .pouncing) == .pounce)
    #expect(NookiClip.choose(frame: frame, yarn: .proud) == .sit)
    #expect(NookiClip.choose(frame: frame, yarn: .returning) == .walk)
  }

  @Test func withoutTheRiggedWalkItKeepsTheOtherClips() {
    let frame = NookiFrame(wake: 1, eyesOpen: true)
    #expect(NookiClip.choose(frame: frame, yarn: .chasing, walks: false) == .idle)
    #expect(NookiClip.choose(frame: frame, yarn: .pouncing, walks: false) == .pounce)
    #expect(NookiClip.choose(frame: NookiFrame(), yarn: .resting, walks: false) == .sleep)
  }

  @Test func theWalkRateMatchesTravelWithinReason() {
    #expect(NookiClip.walkRate(forTravelAt: NookiClip.walkingSpeed) == 1)
    #expect(NookiClip.walkRate(forTravelAt: 0) == 1)
    #expect(NookiClip.walkRate(forTravelAt: 5) == 3)
  }
}

@MainActor @Suite struct NookiBundledRigTests {
  private func bundledCat() async throws -> Entity {
    try await NookiAssets().model("Cat")
  }

  @Test func theBundleLoadsTheTimeline() async throws {
    let cat = try await bundledCat()
    let animator = try #require(NookiCatAnimator(model: cat))
    #expect(cat.availableAnimations.contains { abs($0.definition.duration - 19.167) < 0.01 })
    #expect(try abs(#require(animator.duration(of: .pounce)) - 1.5) < 0.01)
    for clip in NookiClip.allCases where clip.loops {
      #expect(animator.duration(of: clip) == .infinity)
    }
  }

  @Test func theOffsetStandsTheRigOnItsFloor() async throws {
    let cat = try await bundledCat()
    let bounds = cat.visualBounds(relativeTo: nil)
    let offset = try #require(NookiDiorama.mochiOffset(bounds))
    let standing = bounds.min.y * NookiDiorama.mochiScale + offset.y
    #expect(abs(standing) < 0.001)
    #expect(bounds.extents.max() < 1)
  }

  @Test func aClipPlaysAtOnceAndSwitchesWithABlend() async throws {
    let cat = try await bundledCat()
    let animator = try #require(NookiCatAnimator(model: cat))
    animator.play(.sleep, blend: 0)
    #expect(animator.current == .sleep)
    animator.play(.walk, rate: 2)
    #expect(animator.current == .walk)
  }

  @Test func aModelWithoutATimelineHasNoAnimator() {
    #expect(NookiCatAnimator(model: Entity()) == nil)
  }
}
