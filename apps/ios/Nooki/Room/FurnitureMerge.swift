#if DEBUG || LABS_YES
import DecorInterface
import RealityKit
import UIKit

/// The layout a merged copy of the furniture was built for.
struct MergedGroup: Component {
    var layout: DecorLayout
}

/// A piece's own model, taken off while its geometry stands merged into the group.
struct MergedSource: Component {
    var model: ModelComponent
    var grounding: GroundingShadowComponent?
}

/// Static furniture merged per material: the pieces' meshes baked into the stage's space, one model for each material
/// and shadow behaviour, so the stage draws a few meshes where it drew one for every part of every piece. The pieces
/// keep their entities and their meshes, only without a model while merged; `split` gives them back.
enum FurnitureMerge {
    private struct Key: Hashable {
        let material: String
        let casts: Bool
    }

    private struct Bucket {
        var material: any Material
        var textured: Bool
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
    }

    /// Why entities were left out the last time `merge` ran, by reason, for the Labs stats and the tests.
    nonisolated(unsafe) static var rejected: [String: Int] = [:]

    static func layout(in stage: Entity) -> DecorLayout? {
        stage.children.first { $0.name == RoomStats.mergedName }?.components[MergedGroup.self]?.layout
    }

    /// The entities with a model at or under `entity`.
    static func models(under entity: Entity) -> [Entity] {
        var found: [Entity] = []
        func visit(_ entity: Entity) {
            if entity.components.has(ModelComponent.self) || entity.components.has(MergedSource.self) { found.append(entity) }
            entity.children.forEach(visit)
        }
        visit(entity)
        return found
    }

    /// Puts every merged piece's model back and drops the merged copy.
    static func split(_ stage: Entity) {
        for entity in models(under: stage) {
            guard let source = entity.components[MergedSource.self] else { continue }
            entity.components.set(source.model)
            if let grounding = source.grounding { entity.components.set(grounding) }
            entity.components.remove(MergedSource.self)
        }
        stage.children.filter { $0.name == RoomStats.mergedName }.forEach { $0.removeFromParent() }
    }

    /// Merges what can be merged: opaque untextured-or-singly-textured PBR parts of meshes with normals, with no touch
    /// target and no skeleton. The rest of the pieces stay as they are.
    @discardableResult
    static func merge(_ stage: Entity, layout: DecorLayout, receiver: ImageBasedLightReceiverComponent?) -> Int {
        split(stage)
        var buckets: [Key: Bucket] = [:]
        var merged: [Entity] = []
        rejected = [:]
        for holder in stage.children where holder.name.hasPrefix("decor.") {
            for entity in models(under: holder) {
                guard let model = entity.components[ModelComponent.self] else {
                    rejected["no model", default: 0] += 1
                    continue
                }
                guard !entity.components.has(InputTargetComponent.self) else {
                    rejected["touch target", default: 0] += 1
                    continue
                }
                if let reason = append(model, of: entity, in: stage, to: &buckets) {
                    rejected[reason, default: 0] += 1
                } else {
                    merged.append(entity)
                }
            }
        }
        let group = Entity()
        group.name = RoomStats.mergedName
        group.components.set(MergedGroup(layout: layout))
        for (key, bucket) in buckets where !bucket.indices.isEmpty {
            var descriptor = MeshDescriptor(name: "merged")
            descriptor.positions = MeshBuffers.Positions(bucket.positions)
            descriptor.normals = MeshBuffers.Normals(bucket.normals)
            if bucket.textured { descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(bucket.uvs) }
            descriptor.primitives = .triangles(bucket.indices)
            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }
            let entity = ModelEntity(mesh: mesh, materials: [bucket.material])
            if key.casts { entity.components.set(GroundingShadowComponent(castsShadow: true)) }
            if let receiver { entity.components.set(receiver) }
            group.addChild(entity)
        }
        for entity in merged {
            guard let model = entity.components[ModelComponent.self] else { continue }
            entity.components.set(MergedSource(model: model, grounding: entity.components[GroundingShadowComponent.self]))
            entity.components.remove(ModelComponent.self)
            entity.components.remove(GroundingShadowComponent.self)
        }
        stage.addChild(group)
        return group.children.count
    }

    /// Adds every part of `model` to the buckets, in `stage`'s space; the reason, adding nothing, when any part can't merge.
    private static func append(
        _ model: ModelComponent, of entity: Entity, in stage: Entity, to buckets: inout [Key: Bucket]
    ) -> String? {
        let contents = model.mesh.contents
        guard contents.skeletons.isEmpty else { return "skeleton" }
        let casts = entity.components[GroundingShadowComponent.self]?.castsShadow == true
        let toStage = entity.transformMatrix(relativeTo: stage)
        var staged = buckets
        for instance in contents.instances {
            guard let mesh = contents.models[instance.model] else { return "no model" }
            let matrix = toStage * instance.transform
            let linear = simd_float3x3(
                SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
                SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
                SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
            let normalMatrix = linear.inverse.transpose
            let mirrored = linear.determinant < 0
            for part in mesh.parts {
                guard !model.materials.isEmpty else { return "no materials" }
                let material = model.materials[min(part.materialIndex, model.materials.count - 1)]
                guard let pbr = material as? PhysicallyBasedMaterial else { return "material \(type(of: material))" }
                guard isPlain(pbr) else { return "not plain" }
                guard let normals = part.normals else { return "no normals" }
                let positions = Array(part.positions.elements)
                let normalValues = Array(normals.elements)
                guard positions.count == normalValues.count else { return "normals count" }
                let textured = pbr.baseColor.texture != nil
                let uvs = part.textureCoordinates.map { Array($0.elements) }
                if textured, uvs?.count != positions.count { return "uv count" }
                let key = Key(material: MaterialKey.of(pbr), casts: casts)
                var bucket = staged[key] ?? Bucket(material: pbr, textured: textured)
                let base = UInt32(bucket.positions.count)
                bucket.positions += positions.map { point in
                    let world = matrix * SIMD4(point, 1)
                    return SIMD3(world.x, world.y, world.z)
                }
                bucket.normals += normalValues.map { simd_normalize(normalMatrix * $0) }
                if textured, let uvs { bucket.uvs += uvs }
                let indices = part.triangleIndices.map { Array($0.elements) } ?? (0..<UInt32(positions.count)).map { $0 }
                var triangles = indices.map { $0 + base }
                if mirrored {
                    for i in stride(from: 0, to: triangles.count - 2, by: 3) { triangles.swapAt(i + 1, i + 2) }
                }
                bucket.indices += triangles
                staged[key] = bucket
            }
        }
        buckets = staged
        return nil
    }

    /// Opaque, and lit by its base colour alone: the maps a merged copy would have to carry are not carried.
    private static func isPlain(_ material: PhysicallyBasedMaterial) -> Bool {
        guard case .opaque = material.blending else { return false }
        return material.normal.texture == nil && material.roughness.texture == nil && material.metallic.texture == nil
            && material.emissiveColor.texture == nil && material.ambientOcclusion.texture == nil
            && material.clearcoat.texture == nil && material.specular.texture == nil
    }
}
#endif
