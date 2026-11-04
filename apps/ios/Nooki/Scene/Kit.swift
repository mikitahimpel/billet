import RealityKit
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Clay-like materials: matte, slightly warm.
enum Clay {
    static func matte(_ hex: UInt32, roughness: Float = 0.82) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(hex: hex))
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        return m
    }

    static func glow(_ hex: UInt32, intensity: Float) -> PhysicallyBasedMaterial {
        var m = matte(hex)
        m.emissiveColor = .init(color: UIColor(hex: hex))
        m.emissiveIntensity = intensity
        return m
    }
}

extension simd_quatf {
    static let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    static func x(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [1, 0, 0]) }
    static func y(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 1, 0]) }
    static func z(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 0, 1]) }
}

/// Meshes shared by every primitive of the same shape: spheres and cylinders are one unit mesh scaled to size, rounded
/// boxes one mesh per size, since scaling would stretch their corners.
private enum Meshes {
    static let sphere = MeshResource.generateSphere(radius: 1)
    static let cylinder = MeshResource.generateCylinder(height: 1, radius: 1)
    static var boxes: [SIMD4<Float>: MeshResource] = [:]

    static func box(_ w: Float, _ h: Float, _ d: Float, cornerRadius r: Float) -> MeshResource {
        let key = SIMD4(w, h, d, r)
        if let mesh = boxes[key] { return mesh }
        let mesh = MeshResource.generateBox(width: w, height: h, depth: d, cornerRadius: r)
        boxes[key] = mesh
        return mesh
    }
}

/// Primitive builders. Every helper adds the new model as a child and returns it.
extension Entity {
    @discardableResult
    func model(
        _ mesh: MeshResource,
        _ material: some Material,
        at position: SIMD3<Float>,
        scale: SIMD3<Float> = .one,
        rotation: simd_quatf = .identity
    ) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.position = position
        e.scale = scale
        e.orientation = rotation
        addChild(e)
        return e
    }

    @discardableResult
    func box(
        _ w: Float, _ h: Float, _ d: Float, r: Float = 0.01,
        _ material: some Material, at position: SIMD3<Float>, rotation: simd_quatf = .identity
    ) -> ModelEntity {
        let radius = min(r, min(w, min(h, d)) / 2 - 0.0005)
        return model(Meshes.box(w, h, d, cornerRadius: max(radius, 0)), material, at: position, rotation: rotation)
    }

    @discardableResult
    func sphere(
        _ radius: Float, _ material: some Material, at position: SIMD3<Float>,
        scale: SIMD3<Float> = .one, rotation: simd_quatf = .identity
    ) -> ModelEntity {
        model(Meshes.sphere, material, at: position, scale: scale * radius, rotation: rotation)
    }

    @discardableResult
    func cylinder(
        _ height: Float, _ radius: Float, _ material: some Material, at position: SIMD3<Float>,
        scale: SIMD3<Float> = .one, rotation: simd_quatf = .identity
    ) -> ModelEntity {
        model(Meshes.cylinder, material, at: position, scale: scale * [radius, height, radius], rotation: rotation)
    }

    @discardableResult
    func group(at position: SIMD3<Float> = .zero, rotation: simd_quatf = .identity) -> Entity {
        let e = Entity()
        e.position = position
        e.orientation = rotation
        addChild(e)
        return e
    }

    func forEachDescendant(_ body: (Entity) -> Void) {
        for child in children {
            body(child)
            child.forEachDescendant(body)
        }
    }
}
