import Foundation
import RealityKit
import simd

/// Everything the room's real physics does: what is solid, how the ball is made, and how tilt and
/// a flick push it.
///
/// Solid things use their own collision group, so tap targets like the cat's stay out of the ball's
/// way. A solid for each open side of the room keeps the ball in.
@MainActor final class NookiPhysics {
  static let ballRadius: Float = 0.07

  /// Metres per second squared for each g of lean, and the most tilt can push.
  nonisolated private static let accelerationPerG: Float = 6
  nonisolated private static let mostAcceleration: Float = 2.5
  /// Metres per second for each point per second of swipe, and the fastest a flick can throw.
  nonisolated private static let flickPerPoint: Float = 0.0016
  nonisolated private static let fastestFlick: Float = 2.4
  nonisolated private static let roomMin: SIMD3<Float> = [-0.6, -0.2, -0.6]
  nonisolated private static let roomMax: SIMD3<Float> = [0.7, 1.2, 0.7]
  private static let solidGroup = CollisionGroup(rawValue: 1 << 8)
  private static let ballGroup = CollisionGroup(rawValue: 1 << 9)
  /// How much of a piece's footprint is solid: leaves and arms overhang their base.
  private static let footprint: Float = 0.7

  /// The yarn's holder, whose origin is the middle of the ball.
  let ball = ModelEntity()
  private var isHeld = false

  /// Where tilt pushes the ball, in room axes, for a lean in units of g seen from `yaw`.
  /// Leaning to the right rolls it right on screen, and leaning the top away rolls it away.
  nonisolated static func push(lean: SIMD2<Float>, cameraYaw yaw: Float) -> SIMD3<Float> {
    let accelerated = onFloor(lean.x, away: -lean.y, cameraYaw: yaw) * accelerationPerG
    let size = simd_length(accelerated)
    return size > mostAcceleration ? accelerated / size * mostAcceleration : accelerated
  }

  /// The velocity a swipe gives the ball, for a screen velocity in points per second, y down.
  nonisolated static func flick(
    screenVelocity velocity: SIMD2<Float>, cameraYaw yaw: Float
  ) -> SIMD3<Float> {
    let thrown = onFloor(velocity.x, away: -velocity.y, cameraYaw: yaw) * flickPerPoint
    let size = simd_length(thrown)
    return size > fastestFlick ? thrown / size * fastestFlick : thrown
  }

  /// True for a ball that has somehow left the room.
  nonisolated static func isLost(_ position: SIMD3<Float>) -> Bool {
    any(position .< roomMin) || any(position .> roomMax)
  }

  nonisolated private static func onFloor(
    _ right: Float, away: Float, cameraYaw yaw: Float
  ) -> SIMD3<Float> {
    let rightward = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
    let awayward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
    return rightward * right + awayward * away
  }

  /// Puts the floor and the four sides into `room`.
  func buildShell(in room: Entity) {
    let span = Self.roomMax - Self.roomMin
    let middle = (Self.roomMax + Self.roomMin) / 2
    let thick: Float = 0.2
    let shell: [(size: SIMD3<Float>, position: SIMD3<Float>)] = [
      ([span.x + 1, thick, span.z + 1], [middle.x, -thick / 2, middle.z]),
      ([thick, span.y, span.z + 1], [Self.roomMin.x - thick / 2, middle.y, middle.z]),
      ([thick, span.y, span.z + 1], [Self.roomMax.x + thick / 2, middle.y, middle.z]),
      ([span.x + 1, span.y, thick], [middle.x, middle.y, Self.roomMin.z - thick / 2]),
      ([span.x + 1, span.y, thick], [middle.x, middle.y, Self.roomMax.z + thick / 2]),
    ]
    for part in shell {
      let solid = Entity()
      solid.position = part.position
      Self.makeSolid(solid, size: part.size, center: .zero)
      room.addChild(solid)
    }
  }

  /// Gives a piece of furniture a solid base. It moves with the piece.
  func addSolid(to holder: Entity, size: SIMD3<Float>) {
    let solid = Entity()
    let base = size * SIMD3(Self.footprint, 1, Self.footprint)
    Self.makeSolid(solid, size: base, center: [0, size.y / 2, 0])
    holder.addChild(solid)
  }

  /// Makes `ball` a rolling, tappable ball at `position`, its lowest point.
  func prepareBall(at position: SIMD3<Float>) {
    ball.position = position + [0, Self.ballRadius, 0]
    ball.components.set(
      CollisionComponent(
        shapes: [.generateSphere(radius: Self.ballRadius)],
        filter: CollisionFilter(group: Self.ballGroup, mask: Self.solidGroup)))
    ball.components.set(InputTargetComponent())
    var body = PhysicsBodyComponent(
      massProperties: PhysicsMassProperties(mass: 1),
      material: .generate(staticFriction: 0.5, dynamicFriction: 0.4, restitution: 0.55),
      mode: .dynamic)
    body.linearDamping = 0.9
    body.angularDamping = 1.2
    ball.components.set(body)
    ball.components.set(PhysicsMotionComponent())
  }

  func push(_ acceleration: SIMD3<Float>) {
    guard !isHeld, acceleration != .zero else { return }
    ball.addForce(acceleration, relativeTo: nil)
  }

  func setVelocity(_ velocity: SIMD3<Float>) {
    guard !isHeld else { return }
    var motion = ball.components[PhysicsMotionComponent.self] ?? PhysicsMotionComponent()
    motion.linearVelocity = velocity
    ball.components.set(motion)
  }

  /// Stops the ball dead while the cat sits on it, and lets it roll again after.
  func setHeld(_ held: Bool) {
    guard held != isHeld else { return }
    if held { setVelocity(.zero) }
    isHeld = held
    guard var body = ball.components[PhysicsBodyComponent.self] else { return }
    body.mode = held ? .kinematic : .dynamic
    ball.components.set(body)
  }

  func putBack(at position: SIMD3<Float>) {
    setVelocity(.zero)
    ball.setPosition(position + [0, Self.ballRadius, 0], relativeTo: ball.parent)
  }

  private static func makeSolid(_ entity: Entity, size: SIMD3<Float>, center: SIMD3<Float>) {
    entity.components.set(
      CollisionComponent(
        shapes: [.generateBox(size: size).offsetBy(translation: center)],
        filter: CollisionFilter(group: solidGroup, mask: ballGroup)))
    entity.components.set(
      PhysicsBodyComponent(
        massProperties: .default,
        material: .generate(staticFriction: 0.5, dynamicFriction: 0.4, restitution: 0.5),
        mode: .static))
  }
}
