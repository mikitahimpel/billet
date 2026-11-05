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

  @Test func identityIsStableAndNeedsNoCredit() {
    #expect(scene.id == "nooki")
    #expect(scene.title == "Nooki")
    #expect(scene.credit == nil)
  }

  @Test func theSceneShowsAFurnishedRoom() {
    #expect(scene.hasRoom)
  }

  @Test(arguments: [
    "Item_rug", "Item_donutbed", "Item_bookcase", "Item_monstera", "Item_lamp",
    "Item_armchair", "Item_lantern", "Item_print", "Item_teatable", "Item_tower", "Item_yarn",
    "Item_mouse",
  ])
  func shopFurnitureLoads(name: String) async throws {
    let model = try await NookiAssets().model(name)
    #expect(!model.visualBounds(relativeTo: nil).isEmpty)
  }

  @Test func theCompiledFurnitureOpens() async {
    #expect(await NookiAssets.compiled("Room") != nil)
  }

  @Test func theBakedLampStillHasPartsThatGlow() async throws {
    let lamp = try await NookiAssets().model("Item_lamp")
    var glowing = 0
    SceneParts.visit(lamp) { entity in
      for material in entity.components[ModelComponent.self]?.materials ?? [] {
        if let surface = material as? PhysicallyBasedMaterial, surface.emissiveIntensity > 0 {
          glowing += 1
        }
      }
    }
    #expect(glowing > 0)
  }

  @Test func theStandardCatOpens() async throws {
    let cat = try #require(await NookiAssets.compiledCat(CatChoice.standard.model))
    let bounds = cat.visualBounds(relativeTo: nil)
    #expect(bounds.extents.max() > 0.1 && bounds.extents.max() < 1)
  }

  @Test func everyPoseIsAPNG() throws {
    for pose in PetPose.allCases {
      let png = try #require(scene.posePNG(pose))
      #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
  }
}
