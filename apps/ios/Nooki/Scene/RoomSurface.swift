import RealityKit
import SwiftUI
import simd

/// What draws a room and drives its frames: a `RealityView`'s content, or the `RoomRenderLoop`.
@MainActor
protocol RoomSurface {
    /// Calls `handler` for every frame the surface steps the room's scene.
    func updates(_ handler: @escaping (SceneEvents.Update) -> Void) -> EventSubscription
    /// Where `point`, in world space, falls in the surface's own points.
    func project(_ point: SIMD3<Float>) -> CGPoint?
}

extension RealityViewCameraContent: RoomSurface {
    func updates(_ handler: @escaping (SceneEvents.Update) -> Void) -> EventSubscription {
        subscribe(to: SceneEvents.Update.self, on: nil, componentType: nil, handler)
    }

    func project(_ point: SIMD3<Float>) -> CGPoint? { project(point: point, to: .local) }
}

/// A perspective camera looking down its own -z, over a surface `size` points across: the projection `RealityView`
/// does for taps and for the bubble, which the room's own renderer has to do itself.
struct RoomCamera: Equatable {
    /// Camera to world.
    var transform: simd_float4x4
    /// Vertical.
    var fovDegrees: Float
    var size: CGSize

    private var halfTan: Float { tan(fovDegrees * .pi / 360) }
    private var aspect: Float { size.height > 0 ? Float(size.width / size.height) : 1 }

    /// The ray from the camera through a point of the surface, in world space.
    func ray(through point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let x = (2 * Float(point.x / size.width) - 1) * aspect * halfTan
        let y = (1 - 2 * Float(point.y / size.height)) * halfTan
        let local = simd_normalize(SIMD3<Float>(x, y, -1))
        let world = transform * SIMD4<Float>(local, 0)
        return (SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z),
                simd_normalize(SIMD3(world.x, world.y, world.z)))
    }

    /// Nil behind the camera.
    func project(_ world: SIMD3<Float>) -> CGPoint? {
        let c = transform.inverse * SIMD4<Float>(world, 1)
        guard c.z < -1e-4, size.width > 0, size.height > 0 else { return nil }
        let x = c.x / -c.z / (aspect * halfTan)
        let y = c.y / -c.z / halfTan
        return CGPoint(x: Double((x + 1) / 2) * size.width, y: Double((1 - y) / 2) * size.height)
    }
}

/// A ray against a box with sides along the axes (the slab method).
enum RayBox {
    /// How far along `direction` the ray first meets the box, 0 from inside it; nil when it misses.
    static func hit(origin: SIMD3<Float>, direction: SIMD3<Float>, min lo: SIMD3<Float>,
                    max hi: SIMD3<Float>) -> Float? {
        var near: Float = 0
        var far = Float.infinity
        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-9 {
                if origin[axis] < lo[axis] || origin[axis] > hi[axis] { return nil }
                continue
            }
            var t0 = (lo[axis] - origin[axis]) / direction[axis]
            var t1 = (hi[axis] - origin[axis]) / direction[axis]
            if t0 > t1 { swap(&t0, &t1) }
            near = max(near, t0)
            far = min(far, t1)
            if near > far { return nil }
        }
        return near
    }
}

extension CatRoom {
    /// The nearest thing under a touch that takes taps (what `InputTargetComponent` marks), found with a ray against
    /// the boxes of its collision shapes, since the room's own renderer has no view to hit-test.
    func target(at point: CGPoint, camera: RoomCamera) -> Entity? {
        let ray = camera.ray(through: point)
        var best: (entity: Entity, distance: Float)?
        func visit(_ entity: Entity) {
            if entity.isEnabled {
                if entity.components.has(InputTargetComponent.self), let shapes = entity.components[CollisionComponent.self]?.shapes {
                    let origin = entity.convert(position: ray.origin, from: nil)
                    let direction = entity.convert(direction: ray.direction, from: nil)
                    for shape in shapes {
                        let box = shape.bounds
                        guard let t = RayBox.hit(origin: origin, direction: direction, min: box.min, max: box.max)
                        else { continue }
                        let world = entity.convert(position: origin + direction * t, to: nil)
                        let distance = simd_distance(world, ray.origin)
                        if distance < (best?.distance ?? .infinity) { best = (entity, distance) }
                    }
                }
                entity.children.forEach(visit)
            }
        }
        visit(root)
        return best?.entity
    }
}
