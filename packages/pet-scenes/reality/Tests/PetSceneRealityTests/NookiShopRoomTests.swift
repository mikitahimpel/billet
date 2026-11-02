import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
@Suite("Nooki shop room")
struct NookiShopRoomTests {
  private let catalog = ShopCatalog.standard

  private func stubModels() -> NookiShopModels {
    NookiShopModels { _ in
      let box = ModelEntity(mesh: .generateBox(size: [0.2, 0.4, 0.2]))
      return box
    }
  }

  private func settle() async {
    for _ in 0..<20 { await Task.yield() }
  }

  @Test func everyFurniturePieceLoadsAtItsCatalogSize() async throws {
    let models = NookiShopModels()
    for item in catalog.items(in: .furniture) {
      guard case .furniture(_, let fit, let size, _) = item.look else { continue }
      let piece = try #require(await models.furniture(item), "\(item.id)")
      let extents = piece.visualBounds(relativeTo: nil).extents
      let measure = fit == .width ? max(extents.x, extents.z) : extents.y
      #expect(abs(measure - Float(size)) < 0.001, "\(item.id)")
    }
  }

  @Test func everyNonFurnitureItemBuildsWithoutLoading() {
    let models = stubModels()
    for item in catalog.items where item.category != .furniture {
      #expect(models.made(item) != nil, "\(item.id)")
    }
  }

  @Test func placedFurnitureAppearsAndLeaves() async {
    let room = NookiShopRoom(catalog: catalog, models: stubModels())
    let armchair = RoomLayout.Placement(id: "p1", item: "furniture-armchair", x: 0.1, z: 0.2)
    var layout = RoomLayout(placements: [armchair])
    room.apply(layout)
    await settle()
    #expect(room.root.children.count == 1)
    #expect(room.root.children.first?.position.x == 0.1)
    layout = RoomLayout()
    room.apply(layout)
    #expect(room.root.children.isEmpty)
  }

  @Test func applyingTheSameLayoutTwiceDoesNotDuplicate() async {
    let room = NookiShopRoom(catalog: catalog, models: stubModels())
    let layout = RoomLayout(placements: [.init(id: "p1", item: "furniture-lamp", x: 0, z: 0)])
    room.apply(layout)
    room.apply(layout)
    await settle()
    room.apply(layout)
    #expect(room.root.children.count == 1)
  }

  @Test func paintingShowsASlabAndClearingHidesIt() {
    let room = NookiShopRoom(catalog: catalog, models: stubModels())
    room.apply(RoomLayout(wall: "wall-rose"))
    #expect(room.root.children.count == 1)
    #expect(room.root.children.first?.isEnabled == true)
    room.apply(RoomLayout())
    #expect(room.root.children.first?.isEnabled == false)
  }
}
