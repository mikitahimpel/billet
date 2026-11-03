import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor @Suite struct NookiShopRenovationTests {
  private func make() throws -> NookiRenovation {
    let defaults = try #require(UserDefaults(suiteName: "nooki-shop-renovation-\(UUID())"))
    let renovation = NookiRenovation(store: NookiLayoutStore(defaults: defaults))
    renovation.isOn = true
    return renovation
  }

  private func piece(at position: SIMD3<Float>) -> Entity {
    let entity = Entity()
    entity.position = position
    return entity
  }

  @Test func shopPaintTakesTheRoomsAmbientLight() {
    let room = NookiShopRoom()
    room.apply(RoomLayout(wall: "wall-rose"))
    let receiver = ImageBasedLightReceiverComponent(imageBasedLight: Entity())
    room.ambient = receiver
    room.apply(RoomLayout(wall: "wall-rose", floor: "floor-oak"))

    let parts = room.root.children.flatMap(\.children)
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { $0.components.has(ImageBasedLightReceiverComponent.self) })
  }

  @Test func aShopPieceLiftsAndReportsWhereItLands() throws {
    let renovation = try make()
    let stool = piece(at: [0.2, 0, 0.2])
    renovation.register(placement: "stool", holder: stool, half: [0.1, 0.1])
    var landed: (id: String, box: DecorBox)?
    renovation.onPlacementMoved = { landed = ($0, $1) }

    #expect(renovation.carry(stool, to: [-0.3, 0.3]))

    #expect(landed?.id == "stool")
    #expect(abs((landed?.box.centre.x ?? 0) - -0.3) < 0.001)
    #expect(abs((landed?.box.centre.y ?? 0) - 0.3) < 0.001)
  }

  @Test func aShopPieceKeepsItsNewSpotThroughAReset() throws {
    let renovation = try make()
    let stool = piece(at: [0.2, 0, 0.2])
    renovation.register(placement: "stool", holder: stool, half: [0.1, 0.1])
    renovation.carry(stool, to: [-0.3, 0.3])
    renovation.settle()

    renovation.reset(reduceMotion: true)

    #expect(abs(stool.position.x - -0.3) < 0.001)
    #expect(renovation.layout.pieces.isEmpty)
  }

  @Test func theRoomsOwnFurnitureStaysOutOfTheShop() throws {
    let renovation = try make()
    let chair = piece(at: [0.4, 0, -0.4])
    renovation.register("chair", holder: chair, half: [0.1, 0.1])
    var reported = false
    renovation.onPlacementMoved = { _, _ in reported = true }
    renovation.carry(chair, to: [-0.2, 0.2])
    #expect(!reported)
    #expect(renovation.layout.spots?["chair"] != nil)
  }

  @Test func furnitureCannotBeMovedOntoAShopPiece() throws {
    let renovation = try make()
    let stool = piece(at: [0.2, 0, 0.2])
    let chair = piece(at: [-0.3, 0, -0.3])
    renovation.register(placement: "stool", holder: stool, half: [0.15, 0.15])
    renovation.register("chair", holder: chair, half: [0.15, 0.15])
    renovation.carry(chair, to: [0.2, 0.2])
    #expect(renovation.layout.spots?["chair"] == nil)
  }

  @Test func aPieceThatLeftNoLongerTakesUpTheFloor() throws {
    let renovation = try make()
    let stool = piece(at: [0.2, 0, 0.2])
    let chair = piece(at: [-0.3, 0, -0.3])
    renovation.register(placement: "stool", holder: stool, half: [0.15, 0.15])
    renovation.register("chair", holder: chair, half: [0.15, 0.15])
    renovation.unregister(placement: "stool")
    renovation.carry(chair, to: [0.2, 0.2])
    #expect(renovation.layout.spots?["chair"] != nil)
  }

  @Test func aNewPieceAvoidsWhatIsAlreadyThere() throws {
    let renovation = try make()
    let first = try #require(renovation.openSpot(half: [0.15, 0.15]))
    renovation.register(
      placement: "stool", holder: piece(at: SIMD3(first.x, 0, first.y)), half: [0.15, 0.15])
    let second = try #require(renovation.openSpot(half: [0.15, 0.15]))
    #expect(max(abs(first.x - second.x), abs(first.y - second.y)) >= 0.3 - 0.001)
  }

  @Test func aFullFloorHasNoSpot() throws {
    let renovation = try make()
    renovation.addFixed(centre: [0.05, 0.05], half: [1, 1])
    #expect(renovation.openSpot(half: [0.1, 0.1]) == nil)
  }

  @Test func paintingTellsWhichSurfaceChanged() throws {
    let renovation = try make()
    let wall = ModelEntity()
    let floor = ModelEntity()
    renovation.setSurfaces(walls: [wall], floor: floor, wall: .zero, ground: .zero)
    var painted: [RoomSurface] = []
    renovation.onPainted = { painted.append($0) }
    renovation.paint(wall, .moss, reduceMotion: true)
    renovation.paint(floor, .clay, reduceMotion: true)
    renovation.paint(Entity(), .clay, reduceMotion: true)
    #expect(painted == [.wall, .floor])
  }
}
