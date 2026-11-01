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
    "Item_armchair", "Item_lantern", "Item_print", "Item_teatable", "Item_tower", "Item_yarn",
    "Item_mouse",
  ])
  func bundledModelLoads(name: String) async throws {
    let model = try await Entity(named: name, in: .module)
    #expect(!model.visualBounds(relativeTo: nil).isEmpty)
  }

  @Test func mochiHasTheSeparateMeshesTheWakeAnimationSwaps() async throws {
    let model = try await Entity(named: "Cat", in: .module)
    for name in ["Eye1", "Eye_1", "Ear1", "Ear_1", "EarInner1", "EarInner_1", "Bell", "Mouth"] {
      #expect(model.findEntity(named: name) != nil, "missing \(name)")
    }
  }

  @Test func mochiIsStillUnrigged() async throws {
    let model = try await Entity(named: "Cat", in: .module)
    #expect(model.availableAnimations.isEmpty)
  }

  @Test func aNewDioramaBuildsNothingUntilLoaded() {
    #expect(NookiDiorama().entityCount <= 3)
  }

  @Test func theRoomLoadsInFull() async {
    let diorama = NookiDiorama()
    diorama.startLoading()
    await diorama.loading?.value
    #expect(diorama.entityCount > 100)
  }

  @Test func aCancelledCallerStillGetsTheWholeRoom() async {
    let diorama = NookiDiorama()
    let caller = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      diorama.startLoading()
    }
    await caller.value
    await diorama.loading?.value
    #expect(diorama.entityCount > 100)
  }

  @Test func loadingTwiceBuildsOneRoom() async {
    let diorama = NookiDiorama()
    diorama.startLoading()
    let first = diorama.loading
    diorama.startLoading()
    await first?.value
    #expect(diorama.loading == first)
  }

  @Test func posterDecodes() async {
    #expect(await NookiPoster.load() != nil)
  }

  @Test func everyPoseIsAPNG() throws {
    for pose in PetPose.allCases {
      let png = try #require(scene.posePNG(pose))
      #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
  }
}
