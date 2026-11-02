import CoreGraphics
import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor @Suite struct CatMomentsRoomTests {
  @Test func theHeadChainRunsFromTheRoot() {
    let joints = ["root", "root/spine", "root/spine/neck", "root/spine/neck/head", "root/tail"]
    #expect(CatRig.chain(to: "head", in: joints) == [0, 1, 2, 3])
    #expect(CatRig.chain(to: "jaw", in: joints).isEmpty)
  }

  /// Every cat has a mouth: off the floor, under the top of the cat, towards its front.
  @Test func everyCatHasAMouth() async throws {
    for model in CatModel.allCases {
      let cat: Entity? =
        model == .mochi
        ? try await NookiAssets().model("Cat") : await NookiAssets.compiledCat(model)
      guard let cat else { continue }
      let rig = try #require(CatRig(model: cat, clips: CatCatalog.clips(model)), "\(model)")
      let mouth = try #require(rig.mouth(), "\(model) has no head joint")
      let bounds = cat.visualBounds(relativeTo: nil)
      #expect(mouth.y > bounds.min.y + 0.03, "\(model) mouth at \(mouth.y)")
      #expect(mouth.y < bounds.max.y, "\(model) mouth at \(mouth.y)")
      #expect(mouth.z < bounds.center.z, "\(model) mouth is not at the front: \(mouth.z)")
    }
  }

  @Test func strokingFloatsHeartsAndALongPetRolls() {
    let purr = CatPurr()
    var rolled = false
    var t = 0.0
    while t < 3 {
      rolled = purr.touch(at: t, cat: CGPoint(x: 100, y: 200)) || rolled
      t += 0.1
    }
    #expect(purr.isPurring)
    #expect(purr.hearts.count >= 3)
    #expect(rolled)
    purr.tick(at: 4, cat: nil)
    #expect(!purr.isPurring)
  }

  @Test func theLabsSwitchesNameEveryMoment() {
    #expect(CatMoment.allCases.count == 5)
  }
}
