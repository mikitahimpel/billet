import RealityKit
import Testing
import UIKit

@testable import Billet

/// What the Bedroom's furniture costs to draw: the entities, mesh parts, distinct colours and grounding shadows under
/// the room's pivot. The same measure runs on the room before its pieces became movable.
@MainActor
struct BedroomFurnitureCostTests {
    struct Cost {
        var entities = 0
        var models = 0
        var enabledModels = 0
        var parts = 0
        var shadows = 0
        var colours: Set<SIMD4<Float>> = []
        var lights = 0
        var triangles = 0

        init(_ entity: Entity) { visit(entity, enabled: true) }

        private mutating func visit(_ entity: Entity, enabled: Bool) {
            let on = enabled && entity.isEnabled
            entities += 1
            if entity.components[GroundingShadowComponent.self] != nil { shadows += 1 }
            if entity.components[PointLightComponent.self] != nil || entity.components[DirectionalLightComponent.self] != nil {
                lights += 1
            }
            if let model = entity.components[ModelComponent.self] {
                models += 1
                if on { enabledModels += 1 }
                parts += model.mesh.contents.models.reduce(0) { $0 + $1.parts.count }
                if on {
                    for part in model.mesh.contents.models.flatMap({ $0.parts }) {
                        triangles += part.triangleIndices.map { $0.count / 3 } ?? part.positions.count / 3
                    }
                }
                for material in model.materials {
                    if let pbr = material as? PhysicallyBasedMaterial {
                        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                        pbr.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
                        colours.insert(SIMD4(Float(r), Float(g), Float(b), Float(a)))
                    }
                }
            }
            for child in entity.children { visit(child, enabled: on) }
        }
    }

    @Test func printsTheBedroomsDrawCost() async throws {
        let scene = CityRoomScene()
        try await Task.sleep(for: .milliseconds(300))
        Meshes.retessellate(scene.root, smooth: true)
        let cost = Cost(scene.pivot)
        print("bedroom cost: entities \(cost.entities) models \(cost.models) drawn \(cost.enabledModels) parts \(cost.parts) colours \(cost.colours.count) shadows \(cost.shadows) lights \(cost.lights) triangles \(cost.triangles)")
        // Before the pieces were movable: entities 267, models 236 (all drawn), parts 236, colours 53, lights 5. The
        // holders, a blob under each large piece and the ghost may add a few; nothing else may.
        #expect(cost.entities <= 267 + 30)
        #expect(cost.enabledModels <= 236 + 6)
        #expect(cost.parts <= 236 + 6)
        #expect(cost.colours.count <= 53)
        #expect(cost.lights <= 5)
        #expect(cost.shadows == 0)
        // RealityKit's rounded box is 13,068 triangles whatever its radius, its sphere 8,064: 2.08 M for the room. With
        // the facets their radius can show the room is 50 k.
        #expect(cost.triangles <= 55_000)
    }

    /// The full-detail meshes of the Labs switch are RealityKit's, and the lean ones keep the room's entities and parts.
    @Test func theFullDetailMeshesAreTheOldTwoMillionAndComeBack() async throws {
        let scene = CityRoomScene()
        try await Task.sleep(for: .milliseconds(300))
        Meshes.retessellate(scene.root, smooth: true)
        let lean = Cost(scene.pivot)
        Meshes.retessellate(scene.root, smooth: false)
        let full = Cost(scene.pivot)
        print("bedroom full cost: models \(full.models) parts \(full.parts) triangles \(full.triangles) (lean \(lean.triangles))")
        #expect(lean.models == full.models && lean.parts == full.parts && lean.entities == full.entities)
        #expect(full.triangles <= 2_100_000)
        Meshes.retessellate(scene.root, smooth: true)
        #expect(Cost(scene.pivot).triangles == lean.triangles)
    }
}
