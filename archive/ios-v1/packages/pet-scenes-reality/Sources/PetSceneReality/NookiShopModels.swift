import DesignSystem
import Foundation
import Pet
import RealityKit

/// Builds the 3D form of a shop item. Furniture comes from the bundle; treats and material
/// swatches are made from simple shapes in palette colours.
@MainActor
final class NookiShopModels {
  private let loadModel: NookiModelLoader
  private var prototypes: [String: Entity] = [:]

  init(loadModel: NookiModelLoader? = nil) {
    // `if let`, not `??`: the Xcode 27.1 compiler crashes emitting a typed-throws closure wrapped
    // in the autoclosure `??` makes.
    if let loadModel {
      self.loadModel = loadModel
    } else {
      let assets = NookiAssets()
      self.loadModel = { name throws(NookiLoadError) in try await assets.model(name) }
    }
  }

  /// A piece of furniture scaled to its catalog size, standing on y = 0 and centred on x and z.
  /// `nil` when the model cannot be loaded.
  func furniture(_ item: ShopItem) async -> Entity? {
    guard case .furniture(let name, let fit, let size, _) = item.look else { return nil }
    let prototype: Entity
    if let cached = prototypes[name] {
      prototype = cached
    } else {
      guard let loaded = try? await loadModel(name) else { return nil }
      prototypes[name] = loaded
      prototype = loaded
    }
    let model = prototype.clone(recursive: true)
    let bounds = model.visualBounds(relativeTo: nil)
    let measure = fit == .width ? max(bounds.extents.x, bounds.extents.z) : bounds.extents.y
    guard measure > 0 else { return nil }
    let scale = Float(size) / measure
    model.scale = .one * scale
    model.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * scale
    let holder = Entity()
    holder.addChild(model)
    return holder
  }

  /// Everything but furniture, which needs no loading.
  func made(_ item: ShopItem) -> Entity? {
    switch item.look {
    case .furniture: nil
    case .material(let surface, let tone): Self.swatch(surface, tone.swatch)
    case .treat(let shape): Self.treat(shape)
    case .style: nil
    }
  }

  static func material(_ swatch: Swatch) -> PhysicallyBasedMaterial {
    var material = PhysicallyBasedMaterial()
    material.baseColor = .init(
      tint: .init(
        red: CGFloat(swatch.red) / 255, green: CGFloat(swatch.green) / 255,
        blue: CGFloat(swatch.blue) / 255, alpha: 1))
    material.roughness = 0.85
    material.metallic = 0.0
    return material
  }

  private static func part(
    _ mesh: MeshResource, _ swatch: Swatch, at position: SIMD3<Float> = .zero
  ) -> ModelEntity {
    let model = ModelEntity(mesh: mesh, materials: [material(swatch)])
    model.position = position
    return model
  }

  /// A corner of wall and floor, one of them in the material's colour.
  private static func swatch(_ surface: RoomSurface, _ colour: Swatch) -> Entity {
    let wallColour = surface == .wall ? colour : Palette.paperTurned
    let floorColour = surface == .floor ? colour : Palette.woodShade
    let corner = Entity()
    corner.addChild(
      part(
        .generateBox(size: [0.5, 0.36, 0.03]), wallColour,
        at: [0, 0.2, -0.235]))
    corner.addChild(
      part(
        .generateBox(size: [0.5, 0.03, 0.5]), floorColour, at: [0, 0.015, 0]))
    corner.position.y = -0.1
    return corner
  }

  /// A treat about 0.15 m across, standing on y = 0.
  static func treat(_ shape: ShopItem.TreatShape) -> Entity {
    let treat = Entity()
    switch shape {
    case .fish:
      let body = part(
        LowPoly.sphere(radius: 0.06, segments: 14), Palette.woodLit, at: [0, 0.04, 0])
      body.scale = [1.7, 0.7, 0.45]
      let tail = part(
        .generateBox(size: [0.07, 0.07, 0.012]), Palette.woodLit,
        at: [0.12, 0.04, 0])
      tail.orientation = simd_quatf(angle: .pi / 4, axis: [0, 0, 1])
      let eye = part(
        LowPoly.sphere(radius: 0.008, segments: 8), Palette.ink, at: [-0.09, 0.055, 0.025])
      treat.addChild(body)
      treat.addChild(tail)
      treat.addChild(eye)
    case .cookie:
      treat.addChild(
        part(LowPoly.cylinder(height: 0.025, radius: 0.07), Palette.wood, at: [0, 0.0125, 0]))
      for spot in [SIMD3<Float>(-0.03, 0.03, 0.02), [0.03, 0.03, -0.02], [0.0, 0.03, -0.04]] {
        treat.addChild(part(LowPoly.sphere(radius: 0.011, segments: 8), Palette.woodDeep, at: spot))
      }
    case .milk:
      treat.addChild(
        part(LowPoly.cylinder(height: 0.02, radius: 0.08), Palette.clayLit, at: [0, 0.01, 0]))
      treat.addChild(
        part(LowPoly.cylinder(height: 0.006, radius: 0.066), Palette.paper, at: [0, 0.022, 0]))
    }
    return treat
  }
}
