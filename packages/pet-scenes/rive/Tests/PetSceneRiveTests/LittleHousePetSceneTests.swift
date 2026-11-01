import Foundation
import Pet
import PetScene
import Testing

@testable import PetSceneRive

@Suite("LittleHousePetScene")
@MainActor
struct LittleHousePetSceneTests {
  private let scene = LittleHousePetScene()

  @Test func identityIsStable() {
    #expect(scene.id == "little-house")
    #expect(scene.title == "Little House")
    #expect(scene.credit == nil)
  }

  @Test func pacingStaysInsideThePetDeadlines() {
    #expect(LittleHousePetScene.pacing.delivery < PetRunner.deliveryDeadline)
    #expect(LittleHousePetScene.pacing.settling < PetRunner.settlingDeadline)
  }

  @Test func bundledFileHasTheBoundNoteArrivedProperty() {
    #expect(LittleHouseRive() != nil)
  }

  @Test func everyPoseIsAPNG() throws {
    for pose in PetPose.allCases {
      let png = try #require(scene.posePNG(pose))
      #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
  }
}
