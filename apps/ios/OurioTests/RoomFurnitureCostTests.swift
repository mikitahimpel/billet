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

    /// The room's own pieces are the lean models (`Tools/make_room.py`): a third of the full-detail triangles, and the
    /// size each full-detail piece had, to 1 mm, since its footprint, its picking and where the cat
    /// can stand follow it.
    @Test func theFurnitureModelsAreLeanAndKeepTheirSize() async throws {
        func triangles(_ entity: Entity) -> Int {
            var total = 0
            if let model = entity.components[ModelComponent.self] {
                for part in model.mesh.contents.models.flatMap({ $0.parts }) {
                    total += part.triangleIndices.map { $0.count / 3 } ?? part.positions.count / 3
                }
            }
            return total + entity.children.reduce(0) { $0 + triangles($1) }
        }
        // Edge lengths of each full-detail model's box, longest last, as RealityKit measured the full-detail model before it was replaced.
        let sizes: [String: [Float]] = [
            "Base_basket": [0.0926, 0.1740, 0.1740],
            "Base_books": [0.0445, 0.1282, 0.1444],
            "Base_bowls": [0.0300, 0.0900, 0.2000],
            "Base_cattree": [0.2000, 0.2026, 0.3868],
            "Base_donutbed": [0.0977, 0.3495, 0.3522],
            "Base_lamp": [0.1240, 0.1244, 0.2876],
            "Base_nightstand": [0.2173, 0.2300, 0.3012],
            "Base_plant": [0.1420, 0.1420, 0.4072],
            "Base_rug": [0.0125, 0.6660, 0.6660],
            "Base_windowseat": [0.1227, 0.1950, 0.4200],
            "Room_ball": [0.0601, 0.0620, 0.0660],
            "Room_furniture": [0.5054, 0.9664, 0.9754],
            "Room_yarn": [0.1692, 0.1729, 0.2023],
        ]
        var total = 0
        for (name, expected) in sizes.sorted(by: { $0.key < $1.key }) {
            let model = try await Entity(named: name, in: .main)
            total += triangles(model)
            let extents = model.visualBounds(relativeTo: nil).extents
            let got = [extents.x, extents.y, extents.z].sorted()
            for (a, b) in zip(got, expected) { #expect(abs(a - b) < 0.001, "\(name) keeps its size: \(got) against \(expected)") }
        }
        print("furniture cost: lean models \(total) triangles (307,020 at full detail)")
        #expect(total <= 135_000)
    }
}
