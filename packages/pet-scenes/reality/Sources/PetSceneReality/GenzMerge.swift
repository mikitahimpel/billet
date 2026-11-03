import CoreGraphics
import Foundation
import RealityKit

/// Joins the plain parts of a piece into one model per material, so the renderer draws a piece
/// in a handful of calls rather than one per cushion, leg and button.
///
/// Only unnamed parts in an opaque matte material without a texture are joined. Named parts are
/// kept, since the room finds them by name to light, tint or move them, and so are glowing parts,
/// since lamps and LEDs change their material as they come on.
@MainActor
extension GenzKit {
  /// Replaces the plain parts under `piece` with joined models, built once for each `key`.
  func merge(_ piece: Entity, key: String) {
    var groups: [MatteKey: [ModelEntity]] = [:]
    var order: [MatteKey] = []
    NookiDiorama.visit(piece) { entity in
      guard entity !== piece, let model = entity as? ModelEntity, entity.name.isEmpty,
        !entity.components.has(CollisionComponent.self),
        !entity.components.has(InputTargetComponent.self),
        let mesh = model.model?.mesh, model.model?.materials.count == 1,
        let material = model.model?.materials.first as? PhysicallyBasedMaterial,
        let matte = MatteKey(material), mesh.contents.models.count > 0
      else { return }
      if groups[matte] == nil { order.append(matte) }
      groups[matte, default: []].append(model)
    }
    for (index, matte) in order.enumerated() {
      guard let models = groups[matte], models.count > 1 else { continue }
      let cacheKey = "merged \(key) \(index)"
      guard
        let mesh = mergedMeshes[cacheKey]
          ?? Self.joined(models, in: piece).map({ mesh in
            mergedMeshes[cacheKey] = mesh
            return mesh
          })
      else { continue }
      let joined = ModelEntity(mesh: mesh, materials: [models[0].model!.materials[0]])
      piece.addChild(joined)
      for model in models {
        for child in model.children { child.setParent(piece, preservingWorldTransform: true) }
        model.removeFromParent()
      }
    }
  }

  /// One mesh holding every part of `models`, placed as they are under `root`.
  private static func joined(_ models: [ModelEntity], in root: Entity) -> MeshResource? {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    for model in models {
      guard let mesh = model.model?.mesh else { continue }
      let transform = model.transformMatrix(relativeTo: root)
      let turn = simd_float3x3(
        SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
        SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
        SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
      let normalTurn = turn.inverse.transpose
      for instance in mesh.contents.instances {
        let placed = transform * instance.transform
        guard let source = mesh.contents.models[instance.model] else { continue }
        for part in source.parts {
          let start = UInt32(positions.count)
          let partPositions = part.positions.elements
          positions += partPositions.map { point in
            let moved = placed * SIMD4(point, 1)
            return SIMD3(moved.x, moved.y, moved.z)
          }
          let instanceTurn = simd_float3x3(
            SIMD3(
              instance.transform.columns.0.x, instance.transform.columns.0.y,
              instance.transform.columns.0.z),
            SIMD3(
              instance.transform.columns.1.x, instance.transform.columns.1.y,
              instance.transform.columns.1.z),
            SIMD3(
              instance.transform.columns.2.x, instance.transform.columns.2.y,
              instance.transform.columns.2.z))
          let partNormals = part.normals?.elements ?? []
          if partNormals.count == partPositions.count {
            normals += partNormals.map { simd_normalize(normalTurn * (instanceTurn * $0)) }
          } else {
            normals += Array(repeating: [0, 1, 0], count: partPositions.count)
          }
          let partIndices =
            part.triangleIndices?.elements ?? (0..<UInt32(partPositions.count)).map { $0 }
          indices += partIndices.map { $0 + start }
        }
      }
    }
    guard !indices.isEmpty else { return nil }
    var descriptor = MeshDescriptor(name: "genz-merged")
    descriptor.positions = MeshBuffer(positions)
    descriptor.normals = MeshBuffer(normals)
    descriptor.primitives = .triangles(indices)
    return try? MeshResource.generate(from: [descriptor])
  }
}

/// A matte material as a key: its colours, roughness and metalness, for materials without a
/// texture and drawn opaque.
struct MatteKey: Hashable {
  let colour: [CGFloat]
  let emissive: [CGFloat]
  let roughness: Float
  let metallic: Float

  @MainActor
  init?(_ material: PhysicallyBasedMaterial) {
    guard material.baseColor.texture == nil, material.normal.texture == nil,
      material.emissiveColor.texture == nil, material.roughness.texture == nil,
      material.metallic.texture == nil
    else { return nil }
    if case .transparent = material.blending { return nil }
    guard let colour = material.baseColor.tint.cgColor.components, colour.last == 1 else {
      return nil
    }
    self.colour = colour
    emissive = material.emissiveColor.color.cgColor.components ?? []
    roughness = material.roughness.scale
    metallic = material.metallic.scale
  }
}
