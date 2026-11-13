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
        for item in DecorItem.baseItems(in: .living) {
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

    /// The room's own pieces as the app ships them against their lean copies (`Tools/make_room.py` with LEAN=1): the
    /// same parts and materials with the facets their size on screen can show.
    @Test func theLeanCopiesCarryAThirdOfTheTriangles() async throws {
        func triangles(_ entity: Entity) -> Int {
            var total = 0
            if let model = entity.components[ModelComponent.self] {
                for part in model.mesh.contents.models.flatMap({ $0.parts }) {
                    total += part.triangleIndices.map { $0.count / 3 } ?? part.positions.count / 3
                }
            }
            return total + entity.children.reduce(0) { $0 + triangles($1) }
        }
        var full = 0, lean = 0
        var names = DecorItem.baseItems(in: .living).map(\.assetName)
        names += ["Room_furniture", "Room_ball", "Room_yarn"]
        for name in names {
            let own = Cost(try await Entity(named: name, in: .main))
            let copy = Cost(try await Entity(named: Meshes.leanAsset(name), in: .main))
            #expect(copy.parts == own.parts, "\(name) keeps its parts")
            #expect(copy.names == own.names, "\(name) keeps its materials")
            full += triangles(try await Entity(named: name, in: .main))
            lean += triangles(try await Entity(named: Meshes.leanAsset(name), in: .main))
        }
        print("furniture cost: models \(full) triangles, lean copies \(lean)")
        #expect(lean <= 135_000)
        #expect(lean * 2 < full)
    }
}
