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
    private struct Key: Hashable {
        let hex: UInt32
        let roughness: Float
    }

    private static var matteMade: [Key: PhysicallyBasedMaterial] = [:]

    /// One material per tone and roughness, handed out again to every box of it, so RealityKit sees the same material
    /// on a hundred meshes and not a hundred of them.
    static func matte(_ hex: UInt32, roughness: Float = 0.82) -> PhysicallyBasedMaterial {
        let key = Key(hex: hex, roughness: roughness)
        if let m = matteMade[key] { return m }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(hex: hex))
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        matteMade[key] = m
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
enum Meshes {
    private static let sphere = MeshResource.generateSphere(radius: 1)
    private static var smoothSpheres: [Int: MeshResource] = [:]
    static let cylinder = MeshResource.generateCylinder(height: 1, radius: 1)
    private static var boxes: [SIMD4<Float>: MeshResource] = [:]
    private static var smoothBoxes: [SIMD4<Float>: MeshResource] = [:]

    /// Whether boxes made from now on, and those `retessellate` visits, use ``SmoothBox`` and ``SmoothSphere``, and
    /// the furniture models that load from now on are their lean copies. Off draws RealityKit's own. Starts as Labs
    /// left it, so the models of a launch are chosen before the lab exists.
    @MainActor static var smooth = PerfLabMachine.State.saved(in: .standard).isOn(.leanMeshes)

    /// The lean copy's name for a furniture model (`Tools/make_room.py` writes both).
    static func leanAsset(_ name: String) -> String { name + "_lean" }

    @MainActor
    static func box(_ w: Float, _ h: Float, _ d: Float, cornerRadius r: Float) -> MeshResource {
        box(w, h, d, cornerRadius: r, smooth: smooth)
    }

    @MainActor
    static func box(_ w: Float, _ h: Float, _ d: Float, cornerRadius r: Float, smooth: Bool) -> MeshResource {
        let key = SIMD4(w, h, d, r)
        if smooth {
            if let mesh = smoothBoxes[key] { return mesh }
            if let mesh = SmoothBox.mesh(width: w, height: h, depth: d, radius: r) {
                smoothBoxes[key] = mesh
                return mesh
            }
        }
        if let mesh = boxes[key] { return mesh }
        let mesh = MeshResource.generateBox(width: w, height: h, depth: d, cornerRadius: r)
        boxes[key] = mesh
        return mesh
    }

    /// The unit sphere for a sphere whose largest radius is `extent` metres.
    @MainActor
    static func unitSphere(extent: Float, smooth: Bool) -> MeshResource {
        guard smooth else { return sphere }
        let segments = SmoothSphere.segments(radius: extent)
        if let mesh = smoothSpheres[segments] { return mesh }
        guard let mesh = SmoothSphere.mesh(segments: segments) else { return sphere }
        smoothSpheres[segments] = mesh
        return mesh
    }

    /// Gives every box and sphere under `root` the mesh the setting names; the room's look is for the caller to compare.
    @MainActor
    static func retessellate(_ root: Entity, smooth: Bool) {
        func visit(_ entity: Entity) {
            if var model = entity.components[ModelComponent.self] {
                if let shape = entity.components[BoxShape.self] {
                    model.mesh = box(shape.size.x, shape.size.y, shape.size.z, cornerRadius: shape.radius, smooth: smooth)
                    entity.components.set(model)
                } else if let shape = entity.components[SphereShape.self] {
                    model.mesh = unitSphere(extent: shape.extent, smooth: smooth)
                    entity.components.set(model)
                }
            }
            entity.children.forEach(visit)
        }
        visit(root)
    }
}

/// The largest radius of a sphere, in metres, kept so its mesh can be made again at another tessellation.
struct SphereShape: Component {
    var extent: Float
}

/// The size and corner radius a box's mesh was made from, kept so the mesh can be made again at another tessellation.
struct BoxShape: Component {
    var size: SIMD3<Float>
    var radius: Float
}

/// Primitive builders. Every helper adds the new model as a child and returns it.
extension Entity {
    @discardableResult
    func model(
        _ mesh: MeshResource,
        _ material: some Material,
        at position: SIMD3<Float>,
        scale: SIMD3<Float> = .one,
        rotation: simd_quatf = .identity,
        shape: ShellPart.Shape? = nil
    ) -> ModelEntity {
        if skipsForShell(material) { return ModelEntity() }
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.position = position
        e.scale = scale
        e.orientation = rotation
        addChild(e)
        tagForShell(e, material, shape)
        return e
    }

    @discardableResult
    func box(
        _ w: Float, _ h: Float, _ d: Float, r: Float = 0.01,
        _ material: some Material, at position: SIMD3<Float>, rotation: simd_quatf = .identity
    ) -> ModelEntity {
        if skipsForShell(material) { return ModelEntity() }
        let radius = min(r, min(w, min(h, d)) / 2 - 0.0005)
        let e = model(Meshes.box(w, h, d, cornerRadius: max(radius, 0)), material, at: position, rotation: rotation,
                      shape: .box(size: [w, h, d], radius: max(radius, 0)))
        e.components.set(BoxShape(size: [w, h, d], radius: max(radius, 0)))
        return e
    }

    @discardableResult
    func sphere(
        _ radius: Float, _ material: some Material, at position: SIMD3<Float>,
        scale: SIMD3<Float> = .one, rotation: simd_quatf = .identity
    ) -> ModelEntity {
        let extent = radius * max(scale.x, max(scale.y, scale.z))
        let e = model(Meshes.unitSphere(extent: extent, smooth: Meshes.smooth), material, at: position, scale: scale * radius,
                      rotation: rotation, shape: .sphere)
        e.components.set(SphereShape(extent: extent))
        return e
    }

    @discardableResult
    func cylinder(
        _ height: Float, _ radius: Float, _ material: some Material, at position: SIMD3<Float>,
        scale: SIMD3<Float> = .one, rotation: simd_quatf = .identity
    ) -> ModelEntity {
        model(Meshes.cylinder, material, at: position, scale: scale * [radius, height, radius], rotation: rotation,
              shape: .cylinder)
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
