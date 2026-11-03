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
      guard let cat = await NookiAssets.compiledCat(model) else { continue }
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

  /// The room's cat lives on the seat, so a run towards the camera stops at its edge.
  @Test func tripsInTheRoomStayOnTheSeat() throws {
    let layout = GenzLayout.of(.original)
    let surface = try #require(layout.catSurface, "no surface under the cat")
    let home = SIMD2(layout.cat.spot.x, layout.cat.spot.y)
    #expect(all(home .>= surface.min) && all(home .<= surface.max))
    let far = layout.onCatSurface(home + SIMD2(20, 20))
    #expect(all(far .> surface.min) && all(far .< surface.max), "ran off to \(far)")
  }

  /// Moving to turn the room, the finger is never batted at; held still, it is.
  @Test func aFingerTurningTheRoomIsNeverBatted() {
    var rest = CatFingerRest()
    var t = 0.0
    for x in stride(from: 10.0, through: 60, by: 5) {
      rest.moved(toX: x, y: 400, at: t)
      #expect(rest.resting(at: t) == nil)
      t += 1 / 60
    }
    #expect(rest.resting(at: t + CatFingerRest.dwell) != nil)
  }
}
