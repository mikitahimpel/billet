import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
@Suite struct NookiPreviewStageTests {
  private let stage: NookiPreviewStage

  init() {
    stage = NookiPreviewStage(
      models: NookiShopModels(loadModel: { _ throws(NookiLoadError) in
        try? await Task.sleep(for: .milliseconds(50))
        return ModelEntity(mesh: .generateBox(size: 0.2))
      }))
  }

  private var item: ShopItem {
    get throws {
      try #require(
        ShopCatalog.standard.items.first {
          if case .furniture = $0.look { true } else { false }
        })
    }
  }

  /// A cover or a sheet cancels the view's task and its return asks for the same item again.
  @Test func aCancelledLoadIsTriedAgainForTheSameItem() async throws {
    let item = try item
    let cancelled = Task { await stage.show(item) }
    cancelled.cancel()
    await cancelled.value
    #expect(stage.onTable == nil)
    await stage.show(item)
    #expect(stage.onTable == item.id)
  }

  @Test func aSupersededLoadLeavesTheNewerItem() async throws {
    let item = try item
    let other = try #require(
      ShopCatalog.standard.items.first {
        if case .furniture = $0.look { false } else { true }
      })
    let slow = Task { await stage.show(item) }
    await Task.yield()
    await stage.show(other)
    await slow.value
    #expect(stage.onTable == other.id)
  }

  @Test func nothingIsPresentedBeforeAFrameIsDrawn() async throws {
    await stage.show(try item)
    #expect(stage.presented == nil)
  }
}
