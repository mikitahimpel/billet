import Foundation
import Pet
import PetScene
import RealityKit
import Testing

@testable import PetSceneReality

@Suite("NookiPetScene")
@MainActor
struct NookiPetSceneTests {
  private let scene = NookiPetScene()

  @Test func identityIsStableAndCreditsTheSource() throws {
    #expect(scene.id == "nooki")
    #expect(scene.title == "Nooki")
    let credit = try #require(scene.credit)
    #expect(credit.contains("Chill Cat"))
    #expect(credit.contains("Shix"))
    #expect(credit.contains("CC BY 4.0"))
  }

  @Test(arguments: [
    "Cat", "Item_rug", "Item_donutbed", "Item_bookcase", "Item_monstera", "Item_lamp",
  ])
  func bundledModelLoads(name: String) async throws {
    let model = try await Entity(named: name, in: .module)
    #expect(!model.visualBounds(relativeTo: nil).isEmpty)
  }

  @Test func mochiHasTheSeparateMeshesTheWakeAnimationSwaps() async throws {
    let model = try await Entity(named: "Cat", in: .module)
    for name in ["Eye1", "Eye_1", "Ear1", "Ear_1", "EarInner1", "EarInner_1"] {
      #expect(model.findEntity(named: name) != nil, "missing \(name)")
    }
  }

  @Test func mochiIsStillUnrigged() async throws {
    let model = try await Entity(named: "Cat", in: .module)
    #expect(model.availableAnimations.isEmpty)
  }

  @Test func everyPoseIsAPNG() throws {
    for pose in PetPose.allCases {
      let png = try #require(scene.posePNG(pose))
      #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
  }
}
