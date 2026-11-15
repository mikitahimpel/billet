#if DEBUG || LABS_YES
import Foundation
import RealityKit
import UIKit

/// What the visible room asks of RealityKit, counted by walking its live scene once: entities, draw units, lights and
/// shadows. Read on demand from Labs; nothing runs per frame.
struct RoomStats: Equatable, Sendable {
    /// The entity merged copies of several pieces hang under, and the name of the one baked contact-shadow quad.
    static let mergedName = "perf.merged"
    static let blobLayerName = "perf.blobLayer"

    var room = ""
    var tier = ""
    /// Entities that are enabled all the way up, and those in switched-off subtrees.
    var entities = 0
    var disabled = 0
    var models = 0
    /// Material slots on those models, and how many differ by value (see ``MaterialKey``).
    var materialSlots = 0
    var distinctMaterials = 0
    /// Mesh parts: one draw each, in every pass that draws the part.
    var parts = 0
    var triangles = 0
    var directional = 0
    var point = 0
    var spot = 0
    var imageBased = 0
    /// Directional lights that draw the room into a shadow map, and entities that cast into dynamic lights' shadows.
    var shadowMaps = 0
    var dynamicShadowCasters = 0
    var groundingCasters = 0
    var groundingReceivers = 0
    var imageLightReceivers = 0
    /// Contact-shadow quads under pieces, and the one quad that replaces them when the lab bakes them.
    var blobs = 0
    var blobLayers = 0
    var mergedModels = 0
    var emitters = 0
    /// The splat cat: parts drawn now, the file's splats and the share the detail keeps.
    var splatEntities = 0
    var splats: Int?
    var splatKeep: Double?
    /// Scene writes per second since the last reading; empty when no room ran.
    var writeRates: [String] = []

    /// Walks `root` and everything under it that is enabled.
    @MainActor
    init(walking root: Entity, room: String = "", tier: String = "") {
        self.room = room
        self.tier = tier
        var materials: Set<String> = []
        func visit(_ entity: Entity, active: Bool) {
            guard active else {
                disabled += 1
                for child in entity.children { visit(child, active: false) }
                return
            }
            entities += 1
            if let model = entity.components[ModelComponent.self] {
                models += 1
                materialSlots += model.materials.count
                for material in model.materials { materials.insert(MaterialKey.of(material)) }
                let size = Self.size(of: model.mesh)
                parts += size.parts
                triangles += size.triangles
                if entity.parent?.name == Self.mergedName { mergedModels += 1 }
                if entity.name == Self.blobLayerName { blobLayers += 1 }
                if entity.parent?.name.hasPrefix("decor.") == true, model.mesh.bounds.extents.y == 0 { blobs += 1 }
            }
            if entity.components.has(DirectionalLightComponent.self) {
                directional += 1
                if entity.components.has(DirectionalLightComponent.Shadow.self) { shadowMaps += 1 }
            }
            if entity.components.has(PointLightComponent.self) { point += 1 }
            if entity.components.has(SpotLightComponent.self) { spot += 1 }
            if entity.components.has(ImageBasedLightComponent.self) { imageBased += 1 }
            if entity.components.has(ImageBasedLightReceiverComponent.self) { imageLightReceivers += 1 }
            if entity.components.has(ParticleEmitterComponent.self) { emitters += 1 }
            if let shadow = entity.components[GroundingShadowComponent.self] {
                if shadow.castsShadow { groundingCasters += 1 }
                if shadow.receivesShadow { groundingReceivers += 1 }
            }
            if entity.components[DynamicLightShadowComponent.self]?.castsShadow == true { dynamicShadowCasters += 1 }
            for child in entity.children { visit(child, active: child.isEnabled) }
        }
        visit(root, active: root.isEnabled)
        distinctMaterials = materials.count
    }

    @MainActor
    private static func size(of mesh: MeshResource) -> (parts: Int, triangles: Int) {
        if let low = mesh.lowLevelMesh {
            return (low.parts.count, low.parts.reduce(0) { $0 + $1.indexCount / 3 })
        }
        var parts = 0, triangles = 0
        let contents = mesh.contents
        func count(_ model: MeshResource.Model) {
            for part in model.parts {
                parts += 1
                triangles += part.triangleIndices.map { $0.count / 3 } ?? part.positions.count / 3
            }
        }
        // Each instance of a model is drawn on its own.
        if contents.instances.isEmpty {
            contents.models.forEach(count)
        } else {
            for instance in contents.instances {
                if let model = contents.models[instance.model] { count(model) }
            }
        }
        return (parts, triangles)
    }

    /// The splats the cat draws, from her files' header and the detail they were cut to.
    mutating func setSplats(entities: Int, full: Int?, keep: Double) {
        splatEntities = entities
        splatKeep = keep
        splats = full.map { Int((Double($0) * keep).rounded()) }
    }

    var lines: [String] {
        var out = ["room \(room), tier \(tier)"]
        out.append("\(entities) entities (+\(disabled) off), \(models) models, \(parts) parts, \(triangles) tris")
        out.append("\(distinctMaterials) materials by value in \(materialSlots) slots")
        out.append("lights: \(directional) directional (\(shadowMaps) shadow maps), \(point) point, \(spot) spot, \(imageBased) image")
        out.append("shadows: \(groundingCasters) grounding cast, \(groundingReceivers) receive, \(dynamicShadowCasters) dynamic cast, \(imageLightReceivers) ibl receivers")
        out.append("blobs \(blobs), baked layer \(blobLayers), merged models \(mergedModels), emitters \(emitters)")
        if let keep = splatKeep {
            let count = splats.map { "~\($0)" } ?? "?"
            out.append("cat splats \(count) in \(splatEntities) entities, detail \(Int((keep * 100).rounded()))%")
        }
        return out + writeRates
    }

    var line: String { "stats " + lines.joined(separator: "; ") }

    /// What moved since `old`, for reading a change of furniture or of a switch; nil when nothing did.
    func changes(since old: RoomStats) -> String? {
        let pairs: [(String, Int)] = [
            ("entities", entities - old.entities), ("models", models - old.models), ("parts", parts - old.parts),
            ("tris", triangles - old.triangles), ("materials", distinctMaterials - old.distinctMaterials),
            ("point lights", point - old.point), ("shadow maps", shadowMaps - old.shadowMaps),
            ("grounding", groundingCasters - old.groundingCasters), ("blobs", blobs - old.blobs),
        ]
        let moved = pairs.filter { $0.1 != 0 }.map { "\($0.0) \($0.1 > 0 ? "+" : "")\($0.1)" }
        return moved.isEmpty ? nil : "since last: " + moved.joined(separator: ", ")
    }
}

/// A material read as a value: two slots with the same colour, roughness and glow count once, though RealityKit holds
/// them as separate instances.
enum MaterialKey {
    static func of(_ material: any Material) -> String {
        if let pbr = material as? PhysicallyBasedMaterial {
            var parts = ["pbr", pbr.name ?? "", color(pbr.baseColor.tint), "r\(pbr.roughness.scale)", "m\(pbr.metallic.scale)"]
            parts.append("e" + color(pbr.emissiveColor.color) + "\(pbr.emissiveIntensity)")
            parts.append(texture(pbr.baseColor.texture?.resource))
            parts.append("\(pbr.blending)")
            parts.append("\(pbr.faceCulling)")
            return parts.joined(separator: "|")
        }
        if let unlit = material as? UnlitMaterial {
            return ["unlit", unlit.name ?? "", color(unlit.color.tint), texture(unlit.color.texture?.resource)].joined(separator: "|")
        }
        return "\(type(of: material))|\(material.name ?? "")"
    }

    private static func texture(_ resource: TextureResource?) -> String {
        resource.map { "t\(UInt(bitPattern: ObjectIdentifier($0).hashValue))" } ?? "-"
    }

    private static func color(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f,%.3f,%.3f,%.2f", r, g, b, a)
    }
}
#endif
