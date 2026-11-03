import CoreGraphics
import Foundation
import RealityKit

/// Joins the plain parts of a piece into one model per material, so the renderer draws a piece
/// in a handful of calls rather than one per cushion, leg and button.
///
/// Only unnamed parts in an opaque matte material are joined. A textured material joins parts
/// that share its very textures, with any scaling of its texture coordinates carried into the
/// joined mesh's coordinates; one turned or shifted is left alone. Named parts are kept, since the room finds them by name to light, tint or move them, and so are glowing parts,
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
        let matte = MatteKey(material, textures: textures), mesh.contents.models.count > 0,
        !matte.isTextured || Self.hasPlainCoordinates(mesh)
      else { return }
      if groups[matte] == nil { order.append(matte) }
      groups[matte, default: []].append(model)
    }
    for (index, matte) in order.enumerated() {
      guard let models = groups[matte], models.count > 1 else { continue }
      let cacheKey = "merged \(key) \(index)"
      guard
        let mesh = mergedMeshes[cacheKey]
          ?? Self.joined(models, in: piece, textured: matte.isTextured).map({ mesh in
            mergedMeshes[cacheKey] = mesh
            return mesh
          })
      else { continue }
      var material = models[0].model!.materials[0]
      if matte.isTextured, var textured = material as? PhysicallyBasedMaterial {
        textured.textureCoordinateTransform = .init()
        material = textured
      }
      let joined = ModelEntity(mesh: mesh, materials: [material])
      piece.addChild(joined)
      for model in models {
        for child in model.children { child.setParent(piece, preservingWorldTransform: true) }
        model.removeFromParent()
      }
    }
  }

  /// Whether every part of `mesh` has texture coordinates and no second, custom set of them.
  static func hasPlainCoordinates(_ mesh: MeshResource) -> Bool {
    mesh.contents.models.allSatisfy { model in
      model.parts.allSatisfy { part in
        part.textureCoordinates != nil
          && !part.buffers.contains { $0.key.isCustom && $0.value.elementType == .simd2Float }
      }
    }
  }

  /// One mesh holding every part of `models`, placed as they are under `root`. With `textured`,
  /// it keeps their texture coordinates, scaled as each model's material scales them.
  static func joined(_ models: [ModelEntity], in root: Entity, textured: Bool = false)
    -> MeshResource?
  {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var coordinates: [SIMD2<Float>] = []
    var indices: [UInt32] = []
    for model in models {
      guard let mesh = model.model?.mesh else { continue }
      let scale =
        (model.model?.materials.first as? PhysicallyBasedMaterial)?.textureCoordinateTransform
        .scale ?? [1, 1]
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
          if textured {
            let partCoordinates = part.textureCoordinates?.elements ?? []
            coordinates +=
              partCoordinates.count == partPositions.count
              ? partCoordinates.map { $0 * scale }
              : Array(repeating: .zero, count: partPositions.count)
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
    if textured { descriptor.textureCoordinates = MeshBuffer(coordinates) }
    descriptor.primitives = .triangles(indices)
    return try? MeshResource.generate(from: [descriptor])
  }
}

/// A matte material as a key: its colours, roughness, metalness and culling, and the texture it
/// is drawn with, for materials drawn opaque.
struct MatteKey: Hashable {
  let colour: [CGFloat]
  let emissive: [CGFloat]
  let roughness: Float
  let metallic: Float
  /// Which faces are left undrawn, so a two-sided drape never joins one-sided parts.
  let culling: String
  /// The kit's texture the material is drawn with, colour and normal both, if any.
  let texture: GenzTexture?

  var isTextured: Bool { texture != nil }

  /// The key for `material`, or nil when its parts can't be joined: it is see-through, or drawn
  /// with a texture that is not one of `textures`, or with its texture turned or shifted.
  @MainActor
  init?(
    _ material: PhysicallyBasedMaterial,
    textures: [GenzTexture: (colour: TextureResource, normal: TextureResource?)]
  ) {
    guard material.emissiveColor.texture == nil, material.roughness.texture == nil,
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
    culling = String(describing: material.faceCulling)
    let colourTexture = material.baseColor.texture?.resource
    let normalTexture = material.normal.texture?.resource
    if colourTexture == nil, normalTexture == nil {
      texture = nil
      return
    }
    // Texture resources are compared, not hashed: each read of one gives a new object.
    guard
      let made = textures.first(where: { _, made in
        made.colour == colourTexture && made.normal == normalTexture
      })
    else { return nil }
    let transform = material.textureCoordinateTransform
    guard transform.offset == .zero, transform.rotation == 0 else { return nil }
    texture = made.key
  }
}
