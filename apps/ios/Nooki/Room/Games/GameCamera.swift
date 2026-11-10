import Combine
import RealityKit
import SwiftUI

/// The room's camera as the screen sees it: rays from a touch into the room, and points in the room back onto the
/// screen. Read from the camera entity each time, so it matches what was drawn.
struct RoomLens {
    let transform: float4x4
    /// Half the vertical field of view, as its tangent.
    let tanHalf: Float
    let size: CGSize

    init?(camera: Entity?, size: CGSize) {
        guard let camera, let lens = camera.components[PerspectiveCameraComponent.self], size.width > 0,
              size.height > 0 else { return nil }
        transform = camera.transformMatrix(relativeTo: nil)
        let degrees = lens.fieldOfViewInDegrees
        let aspect = Float(size.width / size.height)
        // A horizontal field of view is turned into the vertical one the projection below works in.
        let vertical = lens.fieldOfViewOrientation == .horizontal ? 2 * atan(tan(degrees * .pi / 360) / aspect)
            : degrees * .pi / 180
        tanHalf = tan(vertical / 2)
        self.size = size
    }

    private var aspect: Float { Float(size.width / size.height) }
    private var origin: SIMD3<Float> { SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z) }
    private var right: SIMD3<Float> { simd_normalize(SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)) }
    private var up: SIMD3<Float> { simd_normalize(SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)) }
    /// Cameras look down their -z.
    private var forward: SIMD3<Float> { -simd_normalize(SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)) }

    /// The ray through `point` (in the view's points), in world space.
    func ray(_ point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let x = Float(point.x / size.width) * 2 - 1
        let y = 1 - Float(point.y / size.height) * 2
        let direction = simd_normalize(forward + right * (x * tanHalf * aspect) + up * (y * tanHalf))
        return (origin, direction)
    }

    /// Where the world point `p` lands on screen, nil behind the camera.
    func project(_ p: SIMD3<Float>) -> CGPoint? {
        let d = p - origin
        let depth = simd_dot(d, forward)
        guard depth > 0.001 else { return nil }
        let x = simd_dot(d, right) / (depth * tanHalf * aspect)
        let y = simd_dot(d, up) / (depth * tanHalf)
        return CGPoint(x: CGFloat((x + 1) / 2) * size.width, y: CGFloat((1 - y) / 2) * size.height)
    }

    /// Screen points per meter at world point `p`, for turning a finger's travel into meters on the cat.
    func pointsPerMeter(at p: SIMD3<Float>) -> CGFloat {
        let depth = max(simd_dot(p - origin, forward), 0.01)
        return size.height / CGFloat(2 * depth * tanHalf)
    }
}

/// Brings the room's camera in to frame a game, and lets it go again. The room's own camera rig places the camera
/// each frame; this runs after it and moves the camera from there toward the game's framing, blended in and out so
/// nothing jumps.
@MainActor
final class GameCamera {
    private weak var room: CatRoom?
    private var subscription: (any Cancellable)?
    private(set) var camera: Entity?
    /// Points the frame must hold, in the room's pivot space.
    var focus: [SIMD3<Float>] = []
    /// How much of the screen's narrower side they fill.
    var fill: Float = 0.8
    var viewport = CGSize(width: 390, height: 844)
    private var amount: Float = 0
    private var goal: Float = 1
    private var onGone: (() -> Void)?

    init(room: CatRoom) {
        self.room = room
        guard let scene = room.root.scene else { return }
        camera = scene.performQuery(EntityQuery(where: .has(PerspectiveCameraComponent.self))).first { _ in true }
        subscription = scene.subscribe(to: SceneEvents.Update.self) { [weak self] (event: SceneEvents.Update) in
            MainActor.assumeIsolated { self?.update(Float(event.deltaTime)) }
        }
    }

    /// Lets go at once, for a camera nothing else steers.
    func cancel() {
        subscription?.cancel()
        subscription = nil
        onGone = nil
    }

    /// Eases back to the room's own camera, then calls `done`.
    func release(_ done: @escaping () -> Void) {
        goal = 0
        onGone = done
        if subscription == nil { finish() }
    }

    private func finish() {
        subscription?.cancel()
        subscription = nil
        let done = onGone
        onGone = nil
        done?()
    }

    private func update(_ dt: Float) {
        amount += (goal - amount) * min(1, dt * 3.2)
        if goal == 0, amount < 0.01 { return finish() }
        guard let camera, let room, !focus.isEmpty else { return }
        let base = camera.transformMatrix(relativeTo: nil)
        let eye = SIMD3(base.columns.3.x, base.columns.3.y, base.columns.3.z)
        let back = simd_normalize(SIMD3(base.columns.2.x, base.columns.2.y, base.columns.2.z))
        let points: [SIMD3<Float>] = focus.map { room.pivot.convert(position: $0, to: nil) }
        let center: SIMD3<Float> = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        let radius: Float = points.map { simd_length($0 - center) }.max() ?? 0.1
        let lens = camera.components[PerspectiveCameraComponent.self]
        let tanHalf = tan((lens?.fieldOfViewInDegrees ?? 22) * .pi / 360)
        let aspect = Float(viewport.width / max(viewport.height, 1))
        let narrow = tanHalf * min(aspect, 1)
        let distance = max(radius, 0.05) / (narrow * fill)
        let goalEye: SIMD3<Float> = center + back * distance
        let s: Float = amount * amount * (3 - 2 * amount)
        let blend = SIMD3<Float>(repeating: s)
        // Where the rig is looking: anywhere along its line of sight, as far out as the game's center will be.
        let reach: Float = simd_length(eye - goalEye)
        let looking: SIMD3<Float> = eye - back * reach
        let target = simd_mix(looking, center, blend)
        let position = simd_mix(eye, goalEye, blend)
        camera.look(at: target, from: position, relativeTo: nil)
    }
}
