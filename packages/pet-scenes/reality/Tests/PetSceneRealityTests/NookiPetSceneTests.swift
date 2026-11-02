import CoreGraphics
import Foundation
import Pet
import PetScene
import RealityKit
import Testing
import simd

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

  @Test(arguments: [
    "Item_rug", "Item_donutbed", "Item_bookcase", "Item_monstera", "Item_lamp",
    "Item_armchair", "Item_lantern", "Item_print", "Item_teatable", "Item_tower", "Item_yarn",
    "Item_mouse",
  ])
  func bundledModelLoads(name: String) async throws {
    let model = try await NookiAssets().model(name)
    #expect(!model.visualBounds(relativeTo: nil).isEmpty)
  }

  @Test func theCompiledRoomOpens() async {
    #expect(await NookiAssets.compiled("Room") != nil)
  }

  @Test func theBakedShellMatchesTheSizesInTheCode() async throws {
    let assets = NookiAssets()
    for part in NookiDiorama.shellParts {
      let extents = try await assets.model(part.name).visualBounds(relativeTo: nil).extents
      #expect(simd_distance(extents, part.size) < 0.0001, "\(part.name)")
    }
  }

  @Test func aNewDioramaBuildsNothingUntilLoaded() {
    #expect(NookiDiorama().entityCount <= 3)
  }

  @Test func theRoomLoadsInFull() async {
    let diorama = NookiDiorama()
    diorama.startLoading()
    await diorama.loading?.value
    await diorama.catLoading?.value
    #expect(diorama.entityCount > 70)
    #expect(!diorama.isCatMissing)
  }

  @Test func aCancelledCallerStillGetsTheWholeRoom() async {
    let diorama = NookiDiorama()
    let caller = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      diorama.startLoading()
    }
    await caller.value
    await diorama.loading?.value
    await diorama.catLoading?.value
    #expect(diorama.entityCount > 70)
    #expect(!diorama.isCatMissing)
  }

  @Test func aDrawingShownBeforeTheRoomLoadsReachesTheNote() async throws {
    let context = try #require(
      CGContext(
        data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let diorama = NookiDiorama()
    diorama.show(drawing: try #require(context.makeImage()))
    diorama.startLoading()
    await diorama.loading?.value
    for _ in 0..<300 where !diorama.noteShowsDrawing {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(diorama.noteShowsDrawing)
  }

  @Test func theBakedLampStillHasPartsThatGlow() async throws {
    let lamp = try await NookiAssets().model(NookiFurniture.lampName)
    var glowing = 0
    func visit(_ entity: Entity) {
      for material in entity.components[ModelComponent.self]?.materials ?? [] {
        if let surface = material as? PhysicallyBasedMaterial, surface.emissiveIntensity > 0 {
          glowing += 1
        }
      }
      entity.children.forEach(visit)
    }
    visit(lamp)
    #expect(glowing > 0)
  }

  @Test func loadingTwiceBuildsOneRoom() async {
    let diorama = NookiDiorama()
    diorama.startLoading()
    let first = diorama.loading
    diorama.startLoading()
    await first?.value
    #expect(diorama.loading == first)
  }

  @Test func catStartsBeforeAnyFurniture() async {
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
    diorama.onCatMissing = { reported.append($0) }
    diorama.startLoading()
    await diorama.loading?.value
    await diorama.catLoading?.value
    #expect(diorama.isCatMissing)
    #expect(reported == [true])
    #expect(diorama.root.findEntity(named: NookiDiorama.missingMarkName) != nil)
  }

  @Test func aCatWithNoGeometryIsShownAsMissing() async {
    let diorama = NookiDiorama(loadModel: { _ throws(NookiLoadError) in Entity() })
    diorama.startLoading()
    await diorama.loading?.value
    await diorama.catLoading?.value
    #expect(diorama.isCatMissing)
  }

  @Test func aCatThatHangsNeitherHoldsUpTheRoomNorPassesSilently() async throws {
    let (gate, _) = AsyncStream<Void>.makeStream()
    let diorama = NookiDiorama(
      loadModel: { name throws(NookiLoadError) in
        if name == "Cat" { for await _ in gate {} }
        return Entity()
      },
      catDeadline: .milliseconds(20))
    diorama.startLoading()
    await diorama.loading?.value
    try await Task.sleep(for: .milliseconds(200))
    #expect(diorama.isCatMissing)
  }

  @Test func aLateCatClearsTheMissingMark() async throws {
    let (gate, opening) = AsyncStream<Void>.makeStream()
    let diorama = NookiDiorama(
      loadModel: { name throws(NookiLoadError) in
        if name == "Cat" {
          for await _ in gate {}
          return try await Self.bundled(name)
        }
        return Entity()
      },
      catDeadline: .milliseconds(20))
    diorama.startLoading()
    await diorama.loading?.value
    try await Task.sleep(for: .milliseconds(200))
    #expect(diorama.isCatMissing)
    opening.finish()
    await diorama.catLoading?.value
    #expect(!diorama.isCatMissing)
    #expect(diorama.root.findEntity(named: NookiDiorama.missingMarkName) == nil)
  }

  @Test func aFailedChairLeavesTheCat() async {
    let diorama = NookiDiorama(loadModel: Self.failing("Item_armchair"))
    diorama.startLoading()
    await diorama.loading?.value
    await diorama.catLoading?.value
    #expect(!diorama.isCatMissing)
  }

  @Test func catOffsetRefusesBoundsWithNothingInThem() {
    #expect(NookiDiorama.catOffset(BoundingBox.empty) == nil)
    let broken = BoundingBox(min: [.nan, 0, 0], max: [1, 1, 1])
    #expect(NookiDiorama.catOffset(broken) == nil)
  }

  @Test func catOffsetStandsTheModelOnTheFloorAtItsCentre() throws {
    let bounds = BoundingBox(min: [-0.1, 0.2, 0.1], max: [0.3, 0.4, 0.3])
    let offset = try #require(NookiDiorama.catOffset(bounds))
    let expected = SIMD3<Float>(-0.1, -0.2, -0.2) * NookiDiorama.catScale
    #expect(simd_distance(offset, expected) < 0.0001)
  }

  @Test func theBundledCatHasPlausibleBounds() async throws {
    let cat = try await Self.bundled("Cat")
    let bounds = cat.visualBounds(relativeTo: nil)
    #expect(NookiDiorama.catOffset(bounds) != nil)
    #expect(bounds.extents.max() > 0.1 && bounds.extents.max() < 1)
  }

  private static func failing(_ failed: String) -> NookiModelLoader {
    { name throws(NookiLoadError) in
      if name == failed { throw .unreadable(name, reason: "test") }
      return try await bundled(name)
    }
  }

  /// What the app loads for a name: the standard cat for "Cat", else the bundled model.
  private static func bundled(_ name: String) async throws(NookiLoadError) -> Entity {
    guard name == "Cat" else { return try await NookiAssets().model(name) }
    guard let cat = await NookiAssets.compiledCat(CatChoice.standard.model) else {
      throw .unreadable(name, reason: "no standard cat")
    }
    return cat
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
