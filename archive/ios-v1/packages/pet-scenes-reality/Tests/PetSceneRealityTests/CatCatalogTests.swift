import CoreGraphics
import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@Suite struct CatCatalogTests {
  /// The pounce is timed at 1.5 s and plays once.
  @Test func theStandardCatPouncesOnce() throws {
    let clips = CatCatalog.clips(CatChoice.standard.model)
    #expect(try abs(#require(clips[.pounce]).duration - 1.5) < 0.01)
    #expect(clips[.pounce]?.loops == false)
  }

  @Test func unknownAndEmptyClipsAreSkipped() {
    let table: [String: CatClipRange] = [
      "sit": CatClipRange(trimStart: 1, trimEnd: 3, loops: true),
      "dance": CatClipRange(trimStart: 3, trimEnd: 4, loops: false),
      "yawn": CatClipRange(trimStart: 4, trimEnd: 4, loops: false),
    ]
    let decoded = CatCatalog.decoded(table)
    #expect(Set(decoded.keys) == [.sit])
    #expect(decoded[.sit]?.base == .sit)
  }

  @Test func everyBundledCatHasItsTableAndCoats() {
    for model in CatModel.allCases {
      let clips = CatCatalog.clips(model)
      guard !clips.isEmpty else { continue }
      #expect(clips[.idle] != nil, "\(model)")
      #expect(clips[.sleep] != nil, "\(model)")
      for coat in model.coats where coat != .natural {
        #expect(CatCatalog.coatTexture(model, coat: coat) != nil, "\(model) \(coat)")
      }
    }
  }

  /// Each detailed cat swaps its whole painted texture for a coat, eyes included, keeps its own for
  /// the coat it was made with, and plays every action.
  @MainActor @Test(arguments: [CatModel.detailed, .detailedKitten, .detailedFluffy, .hero])
  func detailedCatsWearTheirCoatTextures(model: CatModel) async throws {
    #expect(CatCatalog.coatTexture(model, coat: .natural) == nil)
    let cat = try #require(await NookiAssets.compiledCat(model))
    let rig = try #require(CatRig(model: cat, clips: CatCatalog.clips(model)))
    for coat in model.coats where coat != .natural {
      let texture = try #require(CatCatalog.coatTexture(model, coat: coat), "\(model) \(coat)")
      #expect(texture.width == 1024)
      #expect(rig.paint(texture) >= 2, "\(model) \(coat): fur and eyes both take the coat")
    }
    // A move with stand-ins is one a cat may lack; every other move each made cat has.
    for action in CatAction.allCases where action.standIns.isEmpty {
      #expect(rig.info[action] != nil, "\(model) \(action)")
    }
  }

  @MainActor @Test func everyBundledCatLoadsAndRigs() async throws {
    for model in CatModel.allCases where !CatCatalog.clips(model).isEmpty {
      let cat = try #require(await NookiAssets.compiledCat(model), "\(model)")
      // Measured before the rig poses it: no cat is wider than the body the rooms keep clear.
      try GenzCatObstacleTests.theBodyFits(model, cat)
      let rig = try #require(CatRig(model: cat, clips: CatCatalog.clips(model)), "\(model)")
      #expect(rig.info[.sleep] != nil || rig.info[.idle] != nil)
      let missing = Set(CatCatalog.clips(model).keys).subtracting(rig.info.keys)
      #expect(missing.isEmpty, "\(model) drops \(missing.map(\.rawValue).sorted())")
      if let palette = CatCatalog.coatTexture(model, coat: .black) {
        #expect(rig.paint(palette) > 0, "\(model) has no material a coat can repaint")
      }
    }
  }

  /// The hero plays its own clip for every action the rooms ask for: lifting (dangle), treats
  /// (sniff), the wave trick and a grabbed hand no longer fall back to stand-ins.
  @MainActor @Test func theHeroHasEveryActionWithoutStandIns() async throws {
    let cat = try #require(await NookiAssets.compiledCat(.hero))
    let rig = try #require(
      CatRig(model: cat, clips: CatCatalog.clips(.hero), anatomy: CatModel.hero.anatomy))
    for action in CatAction.allCases {
      #expect(rig.info[action] != nil, "\(action)")
    }
    #expect(rig.info[.dangle]?.loops == true)
    for action in [CatAction.sniff, .wave, .grab] {
      #expect(rig.info[action]?.loops == false, "\(action)")
    }
  }

  /// The detailed cats loaf in a base of their own, gallop in a loop, and lie down from standing
  /// into the sleeping curl, so the next clip after lying down is the sleep. Grooming, licking
  /// lips, startling and tilting the head are one-shots in their bases.
  @MainActor @Test func theDetailedCatsHaveTheBrainsClips() async throws {
    for model in [CatModel.detailed, .detailedKitten, .detailedFluffy, .hero] {
      let cat = try #require(await NookiAssets.compiledCat(model), "\(model)")
      // Measured before the rig poses it: no cat is wider than the body the rooms keep clear.
      try GenzCatObstacleTests.theBodyFits(model, cat)
      let rig = try #require(CatRig(model: cat, clips: CatCatalog.clips(model)), "\(model)")
      #expect(rig.info[.loaf]?.base == .loaf, "\(model)")
      #expect(rig.info[.loaf]?.loops == true, "\(model)")
      #expect(rig.info[.run]?.loops == true, "\(model)")
      #expect(rig.info[.run]?.base == .stand, "\(model)")
      let lie = try #require(rig.info[.lieDown], "\(model)")
      #expect(lie.base == .stand && lie.ends == .sleep && !lie.loops, "\(model)")
      for action in [CatAction.groomFlank, .groomTail, .lickLips, .headTilt] {
        #expect(rig.info[action]?.base == .sit, "\(model) \(action)")
        #expect(rig.info[action]?.loops == false, "\(model) \(action)")
      }
      #expect(rig.info[.startle]?.base == .stand, "\(model)")
      #expect(rig.info[.carry]?.loops == true, "\(model)")
      #expect(rig.info[.lookUp]?.loops == true && rig.info[.lookUp]?.base == .sit, "\(model)")
      for action in [CatAction.rubSide, .jumpUp, .jumpDown] {
        #expect(rig.info[action]?.base == .stand, "\(model) \(action)")
        #expect(rig.info[action]?.loops == false, "\(model) \(action)")
      }
    }
  }

  @Test func aClipEndsInItsBaseUnlessItSaysOtherwise() throws {
    let json = Data(
      """
      {"lieDown": {"trimStart": 0, "trimEnd": 3.2, "loops": false, "base": "stand", "ends": "sleep"},
       "loaf": {"trimStart": 4, "trimEnd": 10, "loops": true, "base": "loaf"}}
      """.utf8)
    let table = try JSONDecoder().decode([String: CatClipRange].self, from: json)
    let info = CatCatalog.info(CatCatalog.decoded(table))
    #expect(info[.lieDown]?.ends == .sleep)
    #expect(info[.loaf]?.ends == .loaf)
  }

  /// A rig hangs a carried note at its own anatomy's mouth: further out for a bigger head.
  @MainActor @Test func theMouthFollowsTheAnatomy() async throws {
    let cat = try #require(await NookiAssets.compiledCat(.hero))
    let clips = CatCatalog.clips(.hero)
    let made = try #require(CatRig(model: cat, clips: clips, anatomy: .madeCat))
    let hero = try #require(CatRig(model: cat, clips: clips, anatomy: CatModel.hero.anatomy))
    let near = try #require(made.mouth())
    let far = try #require(hero.mouth())
    #expect(far.z < near.z)
    #expect(far.y < near.y)
  }

  /// realitytool drops a timeline's unchanging tail, so the last clip may end a little past it;
  /// a clip that starts past the end, or runs well past it, is not in the timeline.
  @Test func aClipMayEndInTheTimelinesDroppedTail() {
    let tail = CatClipRange(trimStart: 66.2, trimEnd: 68.4, loops: false, base: .stand)
    #expect(CatRig.fits(tail, timelineDuration: 68.2))
    #expect(!CatRig.fits(tail, timelineDuration: 66.0))
    let beyond = CatClipRange(trimStart: 60.0, trimEnd: 69.0, loops: false, base: .stand)
    #expect(!CatRig.fits(beyond, timelineDuration: 68.2))
  }
}
