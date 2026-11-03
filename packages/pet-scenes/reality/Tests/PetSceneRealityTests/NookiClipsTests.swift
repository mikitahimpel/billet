import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@Suite struct NookiClipChoiceTests {
  @Test func theWalkRateMatchesTravelWithinReason() {
    #expect(NookiClip.walkRate(forTravelAt: NookiClip.walkingSpeed) == 1)
    #expect(NookiClip.walkRate(forTravelAt: 0) == 1)
    #expect(NookiClip.walkRate(forTravelAt: 5) == 3)
  }

  @Test func walkingAtTheClipsOwnSpeedKeepsPlantedPawsStill() {
    // One 0.083 m stride a second, each paw down for 62% of it: the stance is quicker than the
    // stride, and travel has to match the stance or the paws skate.
    #expect(abs(NookiClip.pawSpeed - 0.083 / 0.62) < 0.01)
  }

  @Test func runningAtTheClipsOwnSpeedKeepsPlantedPawsStill() {
    // A 0.45 s gallop, each paw down for 36% of it and travelling 0.08 m while down.
    #expect(abs(NookiClip.runPawSpeed - 0.08 / (0.36 * 0.45)) < 0.05)
    #expect(NookiClip.runningSpeed > 3 * NookiClip.walkingSpeed)
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
    for action in [CatAction.idle, .walk, .sit, .sleep, .crouchWiggle] {
      #expect(rig.duration(of: action) == .infinity)
    }
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
