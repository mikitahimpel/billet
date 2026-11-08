import Foundation
import RealityKit
import RoomInterface

extension CatCoat {
    /// Puts this coat's colour texture on the mesh cat loaded from `model` (Cat or CatStanding).
    @MainActor func dress(_ entity: Entity, model: String, in bundle: Bundle = .main) async {
        guard self != .grey, let url = bundle.url(forResource: "\(model)Color-\(rawValue)", withExtension: "jpg"),
              let texture = try? await TextureResource(contentsOf: url, options: .init(semantic: .color))
        else { return }
        var changed = 0
        func paint(_ entity: Entity) {
            guard let model = entity as? ModelEntity, var component = model.model else { return }
            component.materials = component.materials.map { material in
                // The body and fur shells take their colour from the atlas; the eyes, lids and bell have small ones.
                guard var pbr = material as? PhysicallyBasedMaterial,
                      let current = pbr.baseColor.texture?.resource,
                      current.width == texture.width, current.height == texture.height
                else { return material }
                pbr.baseColor.texture = .init(texture)
                changed += 1
                return pbr
            }
            model.model = component
        }
        paint(entity)
        entity.forEachDescendant(paint)
        if changed == 0 { print("\(model) has no coloured material for the \(rawValue) coat") }
    }}

