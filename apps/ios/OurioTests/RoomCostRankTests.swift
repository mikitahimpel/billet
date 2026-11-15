import RealityKit
import RoomInterface
import Testing
import UIKit

@testable import Billet

/// Prints what each piece of a room costs, ranked by triangles, so a reduction is chosen by number rather than by guess.
@MainActor
struct RoomCostRankTests {
    struct Row {
        var name: String
        var tris = 0
        var parts = 0
        var models = 0
        var entities = 0
        var blended = 0
        var textures: [String] = []
    }

    struct Sources {
        var boxes = 0
        var boxTris = 0
        var spheres = 0
        var sphereTris = 0
        var otherModels = 0
        var otherTris = 0
    }

    /// The enabled entities under a room's pivot, outside the cat, grouped by the pivot's child they hang under (a piece of
    /// furniture is one group; the walls, floor and trim the pivot holds directly are one).
    static func rank(_ scene: CatRoom, room: String) -> String {
        var rows: [String: Row] = [:]
        var sources = Sources()
        func visit(_ entity: Entity, group: String) {
            guard entity.isEnabled, entity !== scene.catGroup else { return }
            var row = rows[group] ?? Row(name: group)
            row.entities += 1
            if let model = entity.components[ModelComponent.self] {
                row.models += 1
                var tris = 0
                for part in model.mesh.contents.models.flatMap({ $0.parts }) {
                    row.parts += 1
                    tris += part.triangleIndices.map { $0.count / 3 } ?? part.positions.count / 3
                }
                row.tris += tris
                if entity.components.has(BoxShape.self) {
                    sources.boxes += 1
                    sources.boxTris += tris
                } else if entity.components.has(SphereShape.self) {
                    sources.spheres += 1
                    sources.sphereTris += tris
                } else {
                    sources.otherModels += 1
                    sources.otherTris += tris
                }
                for material in model.materials {
                    if let pbr = material as? PhysicallyBasedMaterial {
                        if case .transparent = pbr.blending { row.blended += 1 }
                        for tex in [pbr.baseColor.texture, pbr.normal.texture, pbr.roughness.texture, pbr.metallic.texture, pbr.ambientOcclusion.texture, pbr.emissiveColor.texture] {
                            if let r = tex?.resource { row.textures.append("\(r.width)x\(r.height)/fmt\(r.pixelFormat.rawValue)/mips\(r.mipmapLevelCount)") }
                        }
                    } else if let unlit = material as? UnlitMaterial {
                        if case .transparent = unlit.blending { row.blended += 1 }
                        if let r = unlit.color.texture?.resource { row.textures.append("\(r.width)x\(r.height)/fmt\(r.pixelFormat.rawValue)/mips\(r.mipmapLevelCount)") }
                    }
                }
            }
            rows[group] = row
            for child in entity.children { visit(child, group: group) }
        }
        func name(_ entity: Entity) -> String { entity.name.isEmpty ? "(unnamed \(type(of: entity)))" : entity.name }
        for child in scene.pivot.children {
            if child.name == "decor" {
                for holder in child.children { visit(holder, group: "piece " + name(holder)) }
            } else if child.components.has(ModelComponent.self) {
                visit(child, group: "shell: boxes, spheres and planes on the pivot")
            } else {
                visit(child, group: "group " + name(child))
            }
        }
        let sorted = rows.values.sorted { $0.tris > $1.tris }
        var out = ["RANK \(room): tris \(sorted.reduce(0) { $0 + $1.tris }) in \(sorted.reduce(0) { $0 + $1.models }) models"]
        out.append("RANK \(room) sources: rounded boxes \(sources.boxes) = \(sources.boxTris) tris, spheres \(sources.spheres) = \(sources.sphereTris), other models \(sources.otherModels) = \(sources.otherTris)")
        for r in sorted.prefix(40) {
            let uniq = Dictionary(grouping: r.textures, by: { $0 }).map { "\($0.value.count)x\($0.key)" }.sorted().joined(separator: ",")
            out.append("RANK \(room) | \(r.name) | tris \(r.tris) parts \(r.parts) models \(r.models) entities \(r.entities) blended \(r.blended) textures[\(uniq)]")
        }
        return out.joined(separator: "\n")
    }

    @Test func printsTheLivingRoomRank() async throws {
        let controller = RoomController()
        controller.load()
        for _ in 0..<600 where !controller.isReady { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .seconds(2))
        let scene = try #require(controller.current)
        print(Self.rank(scene, room: "living"))
    }

    @Test func printsTheBedroomRank() async throws {
        let scene = CityRoomScene()
        try await Task.sleep(for: .seconds(2))
        print(Self.rank(scene, room: "bedroom"))
    }
}
