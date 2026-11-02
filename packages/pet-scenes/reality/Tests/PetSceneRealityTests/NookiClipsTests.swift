import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@Suite struct NookiClipChoiceTests {
  @Test func aSleepingCatSleeps() {
    #expect(NookiClip.choose(frame: NookiFrame(), yarn: .resting) == .sleep)
  }

  @Test func anAwakeCatIdlesAndAWalkingOneWalks() {
    let awake = NookiFrame(wake: 1, eyesOpen: true)
    #expect(NookiClip.choose(frame: awake, yarn: .resting) == .idle)
    var walking = awake
    walking.walk = 0.5
    #expect(NookiClip.choose(frame: walking, yarn: .resting) == .walk)
  }

  @Test func aSettlingCatSitsBeforeSleeping() {
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
    try #require(await NookiAssets.compiledCat(CatChoice.standard.model))
  }

  @Test func theBundleLoadsTheTimeline() async throws {
    let cat = try await bundledCat()
    let rig = try #require(CatRig(model: cat, clips: CatCatalog.clips(CatChoice.standard.model)))
    #expect(try abs(#require(rig.duration(of: .pounce)) - 1.5) < 0.01)
    for clip in NookiClip.allCases where clip != .pounce {
      #expect(rig.duration(of: try #require(CatAction(rawValue: clip.rawValue))) == .infinity)
    }
  }

  @Test func theOffsetStandsTheRigOnItsFloor() async throws {
    let cat = try await bundledCat()
    let bounds = cat.visualBounds(relativeTo: nil)
    let offset = try #require(NookiDiorama.catOffset(bounds))
    let standing = bounds.min.y * NookiDiorama.catScale + offset.y
    #expect(abs(standing) < 0.001)
    #expect(bounds.extents.max() < 1)
  }

  @Test func aClipPlaysAtOnceAndSwitchesWithABlend() async throws {
    let cat = try await bundledCat()
    let withoutStretch = CatCatalog.clips(CatChoice.standard.model).filter { $0.key != .stretch }
    let rig = try #require(CatRig(model: cat, clips: withoutStretch))
    rig.play(.sleep, blend: 0)
    #expect(rig.current == .sleep)
    rig.play(.walk, rate: 2)
    #expect(rig.current == .walk)
    rig.play(.stretch)
    #expect(rig.current == .walk)
  }

  @Test func aModelWithoutATimelineHasNoRig() {
    #expect(CatRig(model: Entity(), clips: CatCatalog.clips(CatChoice.standard.model)) == nil)
  }
}
