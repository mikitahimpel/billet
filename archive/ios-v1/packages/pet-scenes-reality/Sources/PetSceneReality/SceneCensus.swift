import Foundation
import Metal
import PetScene
import RealityKit

/// What a scene asks RealityKit to draw, counted from its entities for a measuring run.
///
/// Draw calls are not counted, since the Simulator cannot show them: `parts` is the number of
/// enabled mesh parts in the main pass, and `shadowParts` the ones that also draw into a shadow
/// map when a light casts shadows.
@MainActor
enum SceneCensus {
  static func of(_ root: Entity) -> String {
    var entities = 0
    var models = 0
    var parts = 0
    var casterParts = 0
    var triangles = 0
    var skinned = 0
    var meshes = Set<ObjectIdentifier>()
    /// Bytes of each texture's top level.
    var textures: [ObjectIdentifier: Double] = [:]
    var formats = Set<String>()
    var lights = 0
    var shadowLights = 0
    var heaviest: [(name: String, triangles: Int)] = []

    func addTexture(_ texture: TextureResource?) {
      guard let texture else { return }
      textures[ObjectIdentifier(texture)] =
        Double(texture.width * texture.height) * bytesPerPixel(texture.pixelFormat)
      formats.insert(String(describing: texture.pixelFormat.rawValue))
    }

    func visit(_ entity: Entity, casts inherited: Bool) {
      guard entity.isEnabled else { return }
      entities += 1
      let casts = entity.components[DynamicLightShadowComponent.self]?.castsShadow ?? inherited
      if entity.components.has(PointLightComponent.self) { lights += 1 }
      if entity.components.has(SpotLightComponent.self) {
        lights += 1
        if entity.components.has(SpotLightComponent.Shadow.self) { shadowLights += 1 }
      }
      if entity.components.has(DirectionalLightComponent.self) {
        lights += 1
        if entity.components.has(DirectionalLightComponent.Shadow.self) { shadowLights += 1 }
      }
      if let model = entity.components[ModelComponent.self] {
        models += 1
        meshes.insert(ObjectIdentifier(model.mesh))
        var here = 0
        for instance in model.mesh.contents.models {
          for part in instance.parts {
            parts += 1
            if casts { casterParts += 1 }
            here += (part.triangleIndices?.count ?? 0) / 3
            if part.jointInfluences != nil { skinned += 1 }
          }
        }
        triangles += here
        heaviest.append((path(entity, mesh: model.mesh), here))
        for material in model.materials {
          if let pbr = material as? PhysicallyBasedMaterial {
            addTexture(pbr.baseColor.texture?.resource)
            addTexture(pbr.normal.texture?.resource)
            addTexture(pbr.emissiveColor.texture?.resource)
            addTexture(pbr.roughness.texture?.resource)
            addTexture(pbr.ambientOcclusion.texture?.resource)
          } else if let unlit = material as? UnlitMaterial {
            addTexture(unlit.color.texture?.resource)
          }
        }
      }
      for child in entity.children { visit(child, casts: casts) }
    }
    visit(root, casts: true)
    let top = heaviest.sorted { $0.triangles > $1.triangles }.prefix(8)
      .map { "\($0.name):\($0.triangles)" }.joined(separator: ",")
    // With a full mip chain.
    let textureMB = textures.values.reduce(0, +) * 4 / 3 / 1_048_576
    return
      "entities=\(entities) models=\(models) meshes=\(meshes.count) parts=\(parts) "
      + "shadowParts=\(shadowLights > 0 ? casterParts : 0) tris=\(triangles) "
      + "skinnedParts=\(skinned) textures=\(textures.count) "
      + "textureMB=\(ScenePerf.format(textureMB)) "
      + "textureFormats=\(formats.sorted().joined(separator: ",")) lights=\(lights) shadowLights=\(shadowLights) "
      + "heaviest=\(top)"
  }

  /// The entity's name with its parent's, or else its mesh's size and where it is.
  private static func path(_ entity: Entity, mesh: MeshResource) -> String {
    let names = [entity.parent?.name ?? "", entity.name].filter { !$0.isEmpty }
    let size = mesh.bounds.extents
    let at = entity.position(relativeTo: nil)
    let name =
      names.isEmpty
      ? String(format: "%.1fx%.1fx%.1f@%.1f/%.1f/%.1f", size.x, size.y, size.z, at.x, at.y, at.z)
      : names.joined(separator: "/")
    return name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ",", with: "_")
  }

  /// How many bytes a pixel of `format` takes on the GPU: a compressed block's bytes over its
  /// pixels, and 4 (RGBA8) for any format not named here.
  static func bytesPerPixel(_ format: MTLPixelFormat) -> Double {
    switch format {
    case .astc_4x4_srgb, .astc_4x4_ldr, .astc_4x4_hdr, .bc7_rgbaUnorm, .bc7_rgbaUnorm_srgb,
      .bc3_rgba, .bc3_rgba_srgb:
      1
    case .astc_6x6_srgb, .astc_6x6_ldr, .astc_6x6_hdr: 16.0 / 36
    case .astc_8x8_srgb, .astc_8x8_ldr, .astc_8x8_hdr: 16.0 / 64
    case .bc1_rgba, .bc1_rgba_srgb: 0.5
    case .r8Unorm, .a8Unorm: 1
    case .rg8Unorm, .r16Float: 2
    case .rgba16Float: 8
    case .rgba32Float: 16
    default: 4
    }
  }
}
