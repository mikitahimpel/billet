import Foundation
import Pet
import RealityKit
import simd

/// Mochi as the app builds her (CatRoom.buildCat), on a bare floor: her four splats, their rigs and
/// the walker that moves them, with no room, brain or camera around.
final class Stage {
  /// What the app's Bedroom draws her at.
  static let scale: Float = 0.68

  /// Points round her standing body on the floor, model units, x across and z along (her nose at -z): the nose,
  /// the cheeks, the shoulders, the flanks and the rump, a little inside her fur.
  static let outline: [SIMD2<Float>] = [
    [0, -0.17], [-0.04, -0.13], [0.04, -0.13], [-0.05, -0.06], [0.05, -0.06], [-0.05, 0.02], [0.05, 0.02],
    [-0.045, 0.08], [0.045, 0.08], [0, 0.1],
  ]

  let group = Entity()
  let walker: CatWalker
  let standing: CatRig
  let seated: CatRig
  let lying: [NookiRestPose: CatRig]
  let floor: Float

  /// Sitting at `at` (the standing splat's origin) facing `yaw`. With `lyingBodies` she has her loaf
  /// and sleep splats, as on a phone that draws splats.
  init(resources: URL, at: SIMD3<Float>, yaw: Float, lyingBodies: Bool = true) throws {
    guard let bundle = Bundle(url: resources) else { throw CatRig.Failure.missing(resources.path) }
    standing = try CatRig(CatRig.Files(named: "MochiStanding", drawn: true, in: bundle))
    seated = try CatRig(CatRig.Files(named: "Mochi", drawn: true, in: bundle))
    var lying: [NookiRestPose: CatRig] = [:]
    if lyingBodies {
      for (pose, name) in [(NookiRestPose.loaf, "MochiLoaf"), (.sleep, "MochiSleep")] {
        let rig = try CatRig(CatRig.Files(named: name, drawn: true, in: bundle))
        rig.entity?.isEnabled = false
        lying[pose] = rig
      }
    }
    self.lying = lying
    group.position = at
    floor = at.y
    walker = CatWalker(
      group: group, standing: standing, seated: seated, bodies: lying, scale: Self.scale, rests: [yaw],
      wandering: false)
    // The brain drives her on a phone: no trips, naps, yawns or washing of her own.
    walker.directed = true
    // CAT_DISSOLVE=<seconds> tries her bodies dissolving into each other in place of the cut.
    if let seconds = ProcessInfo.processInfo.environment["CAT_DISSOLVE"].flatMap(Float.init) {
      walker.dissolve = seconds
    }
    walker.show()
  }

  var rigs: [(name: String, rig: CatRig)] {
    [("MochiStanding", standing), ("Mochi", seated)]
      + lying.map { ($0.key == .loaf ? "MochiLoaf" : "MochiSleep", $0.value) }
  }

  /// The bodies on show, each with its model-to-world transform.
  var shown: [(body: DrawnBody, toWorld: simd_float4x4)] {
    rigs.compactMap { name, rig in
      guard let entity = rig.entity, entity.isEnabled, let body = SplatLoader.drawn[name] else { return nil }
      return (body, toWorld(entity))
    }
  }

  /// How opaque each body on show is, in the order of `shown`.
  var opacities: [Float] {
    rigs.compactMap { name, rig in
      guard let entity = rig.entity, entity.isEnabled, SplatLoader.drawn[name] != nil else { return nil }
      return entity.components[OpacityComponent.self]?.opacity ?? 1
    }
  }

  /// Where the laser dot is, for the picture.
  var dot: SIMD3<Float>?

  var shownName: String { shown.first?.body.name ?? "none" }

  /// Model space of the standing splat to the room.
  var modelToWorld: simd_float4x4 {
    Transform(scale: .init(repeating: Self.scale), rotation: group.orientation, translation: group.position)
      .matrix
  }

  private func toWorld(_ entity: Entity) -> simd_float4x4 {
    modelToWorld * Transform(scale: entity.scale, rotation: entity.orientation, translation: entity.position).matrix
  }
}
