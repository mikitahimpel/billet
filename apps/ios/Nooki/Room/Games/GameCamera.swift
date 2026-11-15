import FeatureGames
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

/// Where a camera stands and what it looks at.
struct CameraPose: Equatable {
    var eye: SIMD3<Float>
    var target: SIMD3<Float>
}

/// Frames a game: takes the pose the room's own camera rig has worked out and moves it toward the game's framing,
/// blended in and out so nothing jumps. The room applies it as the last step of placing its camera (`CatRoom.cameraAdjust`),
/// so nothing else can write the pose over it, and the framing is a function of the points, the lens and the view alone.
@MainActor
final class GameCamera {
    private weak var room: CatRoom?
    private(set) var camera: Entity?
    /// Points the frame must hold, in the room's pivot space.
    var focus: [SIMD3<Float>] = []
    /// How much of the screen's narrower side they fill.
    var fill: Float = 0.9
    /// A lean toward the center, 0...1: the camera comes in a little and slides aside, so what stands near it moves
    /// against the wall behind.
    var push: Float = 0
    var viewport = CGSize(width: 390, height: 844)
    /// The share of the screen's height, from its bottom, a card covers: the subject is framed in what is left above it.
    var covered: Float = 0
    private var lift: Float = 0
    private var distance: Float?
    private var amount: Float = 0
    private var goal: Float = 1
    private var onGone: (() -> Void)?

    init(room: CatRoom) {
        self.room = room
        guard let scene = room.root.scene else { return }
        camera = scene.performQuery(EntityQuery(where: .has(PerspectiveCameraComponent.self))).first { _ in true }
        room.cameraAdjust = { [weak self] dt, pose in self?.adjust(dt, pose) ?? pose }
    }

    /// Lets go at once, for a camera nothing else steers.
    func cancel() {
        room?.cameraAdjust = nil
        onGone = nil
    }

    /// Eases back to the room's own camera, then calls `done`.
    func release(_ done: @escaping () -> Void) {
        goal = 0
        onGone = done
        if room?.cameraAdjust == nil { finish() }
    }

    private func finish() {
        room?.cameraAdjust = nil
        let done = onGone
        onGone = nil
        done?()
    }

    private func adjust(_ dt: Float, _ pose: CameraPose) -> CameraPose {
        amount = GameFraming.smooth(amount, toward: goal, dt: dt, rate: 3.2)
        if goal == 0, amount < 0.01 {
            finish()
            return pose
        }
        guard let camera, let room, !focus.isEmpty else { return pose }
        // The line the room's camera looks along, and the sides of it, as `look(at:from:)` makes them.
        let back = simd_normalize(pose.eye - pose.target)
        let side = simd_normalize(simd_cross([0, 1, 0], back))
        let up = simd_cross(back, side)
        let points: [SIMD3<Float>] = focus.map { room.pivot.convert(position: $0, to: nil) }
        let center: SIMD3<Float> = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        let radius: Float = points.map { simd_length($0 - center) }.max() ?? 0.1
        let lens = camera.components[PerspectiveCameraComponent.self]
        let tanHalf = tan((lens?.fieldOfViewInDegrees ?? 22) * .pi / 360)
        let aspect = Float(viewport.width / max(viewport.height, 1))
        // A view or a lens that changes moves the camera there over a moment; one that does not leaves it still.
        let wanted = GameFraming.distance(radius: radius, tanHalf: tanHalf, aspect: aspect, fill: fill, push: push)
        let held = GameFraming.smooth(distance ?? wanted, toward: wanted, dt: dt, rate: 6)
        distance = held
        let goalEye: SIMD3<Float> = center + back * held + side * (0.035 * push)
        let s: Float = amount * amount * (3 - 2 * amount)
        let blend = SIMD3<Float>(repeating: s)
        // Where the rig is looking: anywhere along its line of sight, as far out as the game's center will be.
        let looking: SIMD3<Float> = pose.eye - back * simd_length(pose.eye - goalEye)
        lift = GameFraming.smooth(lift, toward: covered, dt: dt, rate: 5)
        // The view's center moves down by half of what the card covers, so the subject sits in the middle of the rest.
        let down: SIMD3<Float> = -up * (lift * simd_length(goalEye - center) * tanHalf * s)
        return CameraPose(eye: simd_mix(pose.eye, goalEye, blend) + down,
                          target: simd_mix(looking, center, blend) + down)
    }
}
