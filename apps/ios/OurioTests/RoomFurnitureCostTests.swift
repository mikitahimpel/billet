import DecorInterface
import RealityKit
import RoomInterface
import Testing

@testable import Billet

/// The draw cost of the room's own furniture pieces: what the stage keeps, against the models as they load.
@MainActor
struct RoomFurnitureCostTests {
    private struct Cost {
        var entities = 0
        var parts = 0
        var shadows = 0
        var names: Set<String> = []
        var unnamed = 0

        init(_ entity: Entity) { visit(entity) }

        private mutating func visit(_ entity: Entity) {
            entities += 1
            if entity.components[GroundingShadowComponent.self] != nil { shadows += 1 }
            if let model = entity.components[ModelComponent.self] {
                parts += model.mesh.contents.models.reduce(0) { $0 + $1.parts.count }
                for material in model.materials {
                    if let name = material.name, !name.isEmpty { names.insert(name) } else { unnamed += 1 }
                }
            }
            for child in entity.children { visit(child) }
        }
    }

    @Test func standingPiecesDrawNoMoreThanTheyLoadWith() async throws {
        var loaded = Cost(Entity())
        var counts: [Cost] = []
        for item in DecorItem.baseItems {
            counts.append(Cost(try await Entity(named: item.assetName, in: .main)))
        }
        loaded.entities = counts.reduce(0) { $0 + $1.entities }
        loaded.parts = counts.reduce(0) { $0 + $1.parts }
        loaded.names = counts.reduce(into: []) { $0.formUnion($1.names) }
        loaded.unnamed = counts.reduce(0) { $0 + $1.unnamed }
        // Before: every descendant of every piece carried a grounding shadow.
        let shadowedBefore = loaded.entities

        let stage = DecorStage()
        var ready = false
        stage.onBaseReady = { ready = true }
        stage.apply(RoomDecor(), receiver: nil)
        for _ in 0..<400 where !ready { try await Task.sleep(for: .milliseconds(50)) }
        #expect(ready)

        let kept = Cost(stage.root)
        print("furniture cost: loaded entities \(loaded.entities) parts \(loaded.parts) distinct materials \(loaded.names.count) unnamed \(loaded.unnamed) shadows \(shadowedBefore)")
        print("furniture cost: stage entities \(kept.entities) parts \(kept.parts) distinct materials \(kept.names.count) unnamed \(kept.unnamed) shadows \(kept.shadows)")
        #expect(loaded.unnamed == 0)
        #expect(kept.parts >= loaded.parts)
        #expect(kept.shadows < shadowedBefore)
    }
}
