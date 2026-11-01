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

  @Test func aNewDioramaBuildsNothingUntilLoaded() {
    #expect(NookiDiorama().entityCount <= 3)
  }

  @Test func theRoomLoadsInFull() async {
    let diorama = NookiDiorama()
    diorama.startLoading()
    await diorama.loading?.value
    await diorama.mochiLoading?.value
    #expect(diorama.entityCount > 100)
    #expect(!diorama.isMochiMissing)
  }

  @Test func aCancelledCallerStillGetsTheWholeRoom() async {
    let diorama = NookiDiorama()
    let caller = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      diorama.startLoading()
    }
    await caller.value
    await diorama.loading?.value
    await diorama.mochiLoading?.value
    #expect(diorama.entityCount > 100)
    #expect(!diorama.isMochiMissing)
  }

  @Test func loadingTwiceBuildsOneRoom() async {
    let diorama = NookiDiorama()
    diorama.startLoading()
    let first = diorama.loading
    diorama.startLoading()
    await first?.value
    #expect(diorama.loading == first)
  }

  @Test func mochiStartsBeforeAnyFurniture() async {
    let started = StartedModels()
    let diorama = NookiDiorama(loadModel: { name throws(NookiLoadError) in
      started.names.append(name)
      return Entity()
    })
    diorama.startLoading()
    await diorama.loading?.value
    #expect(started.names.first == "Cat")
    #expect(started.names.count == NookiFurniture.items.count + 1)
  }

  @Test func furnitureLoadsTogetherNotInTurn() async {
    let started = StartedModels()
    let (gate, opening) = AsyncStream<Void>.makeStream()
    let diorama = NookiDiorama(loadModel: { name throws(NookiLoadError) in
      started.names.append(name)
      if started.names.count == NookiFurniture.items.count + 1 { opening.finish() }
      for await _ in gate {}
      return Entity()
    })
    diorama.startLoading()
    await diorama.loading?.value
    #expect(started.names.count == NookiFurniture.items.count + 1)
  }

  @Test func aCatThatFailsIsShownAsMissing() async {
    let diorama = NookiDiorama(loadModel: Self.failing("Cat"))
    var reported: [Bool] = []
    diorama.onMochiMissing = { reported.append($0) }
    diorama.startLoading()
    await diorama.loading?.value
    await diorama.mochiLoading?.value
    #expect(diorama.isMochiMissing)
    #expect(reported == [true])
    #expect(diorama.root.findEntity(named: NookiDiorama.missingMarkName) != nil)
  }

  @Test func aCatWithNoGeometryIsShownAsMissing() async {
    let diorama = NookiDiorama(loadModel: { _ throws(NookiLoadError) in Entity() })
    diorama.startLoading()
    await diorama.loading?.value
    await diorama.mochiLoading?.value
    #expect(diorama.isMochiMissing)
  }

  @Test func aCatThatHangsNeitherHoldsUpTheRoomNorPassesSilently() async throws {
    let (gate, _) = AsyncStream<Void>.makeStream()
    let diorama = NookiDiorama(
      loadModel: { name throws(NookiLoadError) in
        if name == "Cat" { for await _ in gate {} }
        return Entity()
      },
      mochiDeadline: .milliseconds(20))
    diorama.startLoading()
    await diorama.loading?.value
    try await Task.sleep(for: .milliseconds(200))
    #expect(diorama.isMochiMissing)
  }

  @Test func aLateCatClearsTheMissingMark() async throws {
    let (gate, opening) = AsyncStream<Void>.makeStream()
    let diorama = NookiDiorama(
      loadModel: { name throws(NookiLoadError) in
        if name == "Cat" {
          for await _ in gate {}
          return try await NookiFurniture.bundledModel(name)
        }
        return Entity()
      },
      mochiDeadline: .milliseconds(20))
    diorama.startLoading()
    await diorama.loading?.value
    try await Task.sleep(for: .milliseconds(200))
    #expect(diorama.isMochiMissing)
    opening.finish()
    await diorama.mochiLoading?.value
    #expect(!diorama.isMochiMissing)
    #expect(diorama.root.findEntity(named: NookiDiorama.missingMarkName) == nil)
  }

  @Test func aFailedChairLeavesTheCat() async {
    let diorama = NookiDiorama(loadModel: Self.failing("Item_armchair"))
    diorama.startLoading()
    await diorama.loading?.value
    await diorama.mochiLoading?.value
    #expect(!diorama.isMochiMissing)
  }

  @Test func mochiOffsetRefusesBoundsWithNothingInThem() {
    #expect(NookiDiorama.mochiOffset(BoundingBox.empty) == nil)
    let broken = BoundingBox(min: [.nan, 0, 0], max: [1, 1, 1])
    #expect(NookiDiorama.mochiOffset(broken) == nil)
  }

  @Test func mochiOffsetStandsTheModelOnTheFloorAtItsCentre() throws {
    let bounds = BoundingBox(min: [-0.1, 0.2, 0.1], max: [0.3, 0.4, 0.3])
    let offset = try #require(NookiDiorama.mochiOffset(bounds))
    let expected = SIMD3<Float>(-0.1, -0.2, -0.2) * NookiDiorama.mochiScale
    #expect(simd_distance(offset, expected) < 0.0001)
  }

  @Test func theBundledCatHasPlausibleBounds() async throws {
    let cat = try await NookiFurniture.bundledModel("Cat")
    let bounds = cat.visualBounds(relativeTo: nil)
    #expect(NookiDiorama.mochiOffset(bounds) != nil)
    #expect(bounds.extents.max() > 0.1 && bounds.extents.max() < 1)
  }

  private static func failing(_ failed: String) -> NookiModelLoader {
    { name throws(NookiLoadError) in
      if name == failed { throw .unreadable(name, reason: "test") }
      return try await NookiFurniture.bundledModel(name)
    }
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

@MainActor private final class StartedModels: Sendable {
  var names: [String] = []
}
