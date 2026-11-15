import DecorInterface
import RealityKit
import RoomInterface
import Testing
import UIKit

@testable import Billet

/// Labs → Performance's room stats: what the walk counts, and the numbers the two rooms are drawn with.
@MainActor
struct RoomStatsTests {
    @Test func theWalkCountsWhatIsThere() {
        let root = Entity()
        let sun = Entity()
        sun.components.set(DirectionalLightComponent())
        sun.components.set(DirectionalLightComponent.Shadow())
        root.addChild(sun)
        let lamp = Entity()
        lamp.components.set(PointLightComponent())
        root.addChild(lamp)

        let red = Clay.matte(0xC0392B), alsoRed = Clay.matte(0xC0392B, roughness: 0.82), blue = Clay.matte(0x2980B9)
        let box = MeshResource.generateBox(size: 1)
        let piece = ModelEntity(mesh: box, materials: [red, blue])
        piece.components.set(GroundingShadowComponent(castsShadow: true))
        root.addChild(piece)
        let twin = ModelEntity(mesh: box, materials: [alsoRed])
        root.addChild(twin)
        let off = ModelEntity(mesh: box, materials: [red])
        off.isEnabled = false
        let underOff = ModelEntity(mesh: box, materials: [red])
        off.addChild(underOff)
        root.addChild(off)

        let stats = RoomStats(walking: root, room: "test", tier: "full")
        #expect(stats.entities == 5)
        #expect(stats.disabled == 2)
        #expect(stats.models == 2)
        #expect(stats.materialSlots == 3)
        #expect(stats.distinctMaterials == 2)
        #expect(stats.parts == 2)
        #expect(stats.triangles == 24)
        #expect(stats.directional == 1 && stats.shadowMaps == 1 && stats.point == 1)
        #expect(stats.groundingCasters == 1)
        #expect(stats.line.contains("5 entities (+2 off)"))
    }

    @Test func theChangeSinceTheLastReadingNamesWhatMoved() {
        let root = Entity()
        let before = RoomStats(walking: root)
        root.addChild(ModelEntity(mesh: .generateBox(size: 1), materials: [Clay.matte(0xFFFFFF)]))
        let after = RoomStats(walking: root)
        #expect(after.changes(since: before)?.contains("models +1") == true)
        #expect(after.changes(since: after) == nil)
    }

    @Test func theLivingRoomsCostIsCountedAndMovesWithTheFurniture() async throws {
        let controller = RoomController()
        controller.load()
        for _ in 0..<600 where !controller.isReady { try await Task.sleep(for: .milliseconds(50)) }
        #expect(controller.isReady)
        let stats = try #require(controller.roomStats(tier: .full))
        print("room stats: \(stats.line)")
        #expect(stats.room == "living")
        #expect(stats.directional >= 1 && stats.shadowMaps >= 1 && stats.point >= 3)
        #expect(stats.parts >= stats.models)
        #expect(stats.blobs > 0)

        // A piece stowed leaves the room: the walk after it counts one holder fewer.
        let layout = controller.decor.layout
        let first = try #require(layout.standing.first)
        controller.showDecor(RoomDecor(layout: DecorLayout(placements: layout.placements, stored: layout.stored.union([first.item]))))
        let after = try #require(controller.roomStats(tier: .full))
        print("room stats after stowing \(first.item): \(after.line); \(after.changes(since: stats) ?? "unchanged")")
        #expect(after.entities < stats.entities)
    }

    @Test func theBedroomsCostIsCounted() throws {
        let room = CityRoomScene()
        let stats = RoomStats(walking: room.root, room: "bedroom", tier: "full")
        print("room stats: \(stats.line)")
        #expect(stats.directional >= 2 && stats.point >= 4)
        #expect(stats.shadowMaps >= 1)
    }
}
