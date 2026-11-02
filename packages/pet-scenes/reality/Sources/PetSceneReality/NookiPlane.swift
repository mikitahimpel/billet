import Foundation
import RealityKit
import simd

/// A note's flight into the room, as plain numbers.
///
/// The plane circles the room until a tap catches it, or the cat leaps for it. Either way the rest of
/// the delivery plays from the catch, and always ends inside the delivery's fixed length.
struct NookiPlaneFlight: Equatable {
  struct Pose: Equatable {
    var position: SIMD3<Float>
    /// Which way the nose points, as a unit vector.
    var heading: SIMD3<Float>
    /// Roll into the turn, in radians.
    var bank: Float
  }

  /// When the cat catches a plane nobody tapped.
  static let catCatchesAt = 2.4
  /// How long a tapped plane takes to reach the cat.
  static let swoopLength = 0.35

  private static let leapLength = 0.45
  /// Where the delivery's own timeline picks up from a catch, with the note in the cat's care.
  private static let choreographyAfterCatch = 1.6
  /// Where it waits until then, with the cat awake and looking.
  private static let choreographyWhileFlying = 1.1
  private static let path: [SIMD3<Float>] = [
    [1.5, 1.25, 0.5], [0.85, 1.05, 0.55], [0.2, 0.9, 0.55], [-0.28, 0.8, 0.15],
    [-0.1, 0.72, -0.3], [0.32, 0.62, -0.1], [0.05, 0.5, 0.12],
  ]

  private(set) var tappedAt: Double?

  /// When the plane reaches the cat.
  var caughtAt: Double {
    tappedAt.map { $0 + Self.swoopLength } ?? Self.catCatchesAt
  }

  func isCaught(at elapsed: Double) -> Bool {
    elapsed >= caughtAt
  }

  /// Catches the plane, unless it has already been caught.
  mutating func tap(at elapsed: Double) {
    guard tappedAt == nil, !isCaught(at: elapsed) else { return }
    tappedAt = elapsed
  }

  /// Where the delivery's timeline should be at `elapsed` seconds into the delivery.
  func choreographyTime(_ elapsed: Double) -> Double {
    guard isCaught(at: elapsed) else { return min(elapsed, Self.choreographyWhileFlying) }
    return Self.choreographyAfterCatch + (elapsed - caughtAt)
  }

  /// Height of the cat's leap for a plane nobody tapped, from 0 to 1.
  func leap(_ elapsed: Double) -> Float {
    guard tappedAt == nil else { return 0 }
    let start = Self.catCatchesAt - Self.leapLength
    guard (start...Self.catCatchesAt).contains(elapsed) else { return 0 }
    return NookiChoreography.arch((elapsed - start) / Self.leapLength / 2 + 0.25)
  }

  func pose(at elapsed: Double, cat: SIMD3<Float>) -> Pose {
    let flown = Self.point(tappedAt ?? elapsed)
    guard let tappedAt else { return Self.pose(at: flown, after: elapsed) }
    let share = Float(min((elapsed - tappedAt) / Self.swoopLength, 1))
    let swoop = mix(flown, cat, t: share * share)
    let next = mix(flown, cat, t: min(share + 0.1, 1))
    return Pose(
      position: swoop, heading: Self.direction(from: swoop, to: next, fallback: [0, -1, 0]),
      bank: 0)
  }

  private static func pose(at position: SIMD3<Float>, after elapsed: Double) -> Pose {
    let ahead = point(elapsed + 0.05)
    let heading = direction(from: position, to: ahead, fallback: [-1, 0, 0])
    let later = direction(from: ahead, to: point(elapsed + 0.1), fallback: heading)
    return Pose(position: position, heading: heading, bank: simd_cross(heading, later).y * 18)
  }

  private static func direction(
    from: SIMD3<Float>, to: SIMD3<Float>, fallback: SIMD3<Float>
  ) -> SIMD3<Float> {
    let gap = to - from
    return simd_length(gap) > 0.0001 ? simd_normalize(gap) : fallback
  }

  /// A smooth curve through `path`, reaching its end when the cat would catch the plane.
  private static func point(_ elapsed: Double) -> SIMD3<Float> {
    let along = Float(min(max(elapsed / catCatchesAt, 0), 1)) * Float(path.count - 1)
    let index = min(Int(along), path.count - 2)
    let (a, b, c, d) = (
      path[max(index - 1, 0)], path[index], path[index + 1], path[min(index + 2, path.count - 1)]
    )
    let t = along - Float(index)
    let slope: SIMD3<Float> = c - a
    let bend: SIMD3<Float> = (a * 2) - (b * 5) + (c * 4) - d
    let twist: SIMD3<Float> = (b * 3) - a - (c * 3) + d
    let offset: SIMD3<Float> = (slope + (bend + twist * t) * t) * t
    return b + offset * 0.5
  }
}

/// The folded paper in the room: two wings that carry the drawing.
@MainActor final class NookiPaperPlane {
  let entity = Entity()
  private var wings: ModelEntity?

  init(paper: PhysicallyBasedMaterial) {
    entity.name = NookiTarget.plane.rawValue
    entity.isEnabled = false
    if let mesh = try? MeshResource.generate(from: [Self.wingsDescriptor()]) {
      let wings = ModelEntity(mesh: mesh, materials: [paper])
      entity.addChild(wings)
      self.wings = wings
    }
    // A generous target: the plane is small and moving.
    entity.components.set(
      CollisionComponent(shapes: [.generateSphere(radius: 0.26)]))
    entity.components.set(InputTargetComponent())
  }

  func setPaper(_ paper: PhysicallyBasedMaterial) {
    wings?.model?.materials = [paper]
  }

  func show(_ pose: NookiPlaneFlight.Pose) {
    entity.position = pose.position
    entity.orientation =
      simd_quatf(from: [0, 0, -1], to: pose.heading)
      * simd_quatf(angle: pose.bank, axis: [0, 0, 1])
  }

  /// A dart seen from above: a nose at -z and two wings folded up from a central keel, mapped so
  /// that the sheet's picture lies across both.
  private static func wingsDescriptor() -> MeshDescriptor {
    let positions: [SIMD3<Float>] = [
      [0, 0, -0.17],
      [0, -0.02, 0.13],
      [-0.12, 0.035, 0.13],
      [0.12, 0.035, 0.13],
    ]
    var mesh = MeshDescriptor(name: "paper-plane")
    mesh.positions = MeshBuffers.Positions(positions)
    mesh.textureCoordinates = MeshBuffers.TextureCoordinates([
      SIMD2(0.5, 1), SIMD2(0.5, 0), SIMD2(0, 0), SIMD2(1, 0),
    ])
    mesh.normals = MeshBuffers.Normals(Array(repeating: SIMD3<Float>(0, 1, 0), count: 4))
    mesh.primitives = .triangles([0, 2, 1, 0, 1, 3, 0, 1, 2, 0, 3, 1])
    return mesh
  }
}
