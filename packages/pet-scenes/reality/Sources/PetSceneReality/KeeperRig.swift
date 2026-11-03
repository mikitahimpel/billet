import CoreGraphics
import Foundation
import OSLog
import Pet
import RealityKit

/// A loaded shopkeeper: its named joints, each kept with its rest transform, and a pose applied on
/// top. Every keeper is made with the same joints (see `scripts/make_shopkeepers.py`), so any of
/// them moves the same way.
@MainActor
final class KeeperRig {
  static let folder = "Shopkeepers"
  static let joints = [
    "body", "head", "eye_L", "eye_R", "ear_L", "ear_R", "arm_L", "arm_R", "tail",
  ]

  let entity: Entity
  private var rest: [String: (entity: Entity, transform: Transform)] = [:]
  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "KeeperRig")

  /// `nil` when the model lacks the body or the head, which every pose moves.
  init?(model: Entity) {
    entity = model
    for name in Self.joints {
      guard let joint = model.findEntity(named: name) else { continue }
      rest[name] = (joint, joint.transform)
    }
    guard rest["body"] != nil, rest["head"] != nil else { return nil }
  }

  var head: Entity? { rest["head"]?.entity }

  /// Where the keeper's paws are now, between them, relative to `entity`: where it holds what it
  /// hands over. Each paw hangs `length` model units down its arm.
  func paws(relativeTo entity: Entity?, length: Float = 0.33) -> SIMD3<Float>? {
    guard let left = rest["arm_L"]?.entity, let right = rest["arm_R"]?.entity else { return nil }
    let tip = SIMD3<Float>(0, -length, 0)
    return (left.convert(position: tip, to: entity) + right.convert(position: tip, to: entity)) / 2
  }

  static func resourceName(_ keeper: Shopkeeper) -> String {
    "Keeper_\(keeper.rawValue)"
  }

  /// The keeper's model from its compiled file, or `nil` when it is missing or will not open.
  static func load(_ keeper: Shopkeeper) async -> Entity? {
    let name = resourceName(keeper)
    guard
      let url = Bundle.module.url(forResource: name, withExtension: "reality", subdirectory: folder)
    else {
      log.error("No file for keeper \(name, privacy: .public)")
      return nil
    }
    do {
      return try await Entity(contentsOf: url)
    } catch {
      log.error("\(name, privacy: .public): \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  func apply(_ pose: KeeperPose) {
    set("body") { transform in
      transform.translation.y += pose.hop
      transform.rotation *=
        simd_quatf(angle: pose.sway, axis: [0, 0, 1])
        * simd_quatf(angle: pose.bow, axis: [1, 0, 0])
      transform.scale *= SIMD3(1, 1 + pose.breath, 1 + pose.breath * 0.5)
    }
    set("head") { transform in
      transform.rotation *=
        simd_quatf(angle: pose.headYaw, axis: [0, 1, 0])
        * simd_quatf(angle: -pose.headPitch, axis: [1, 0, 0])
        * simd_quatf(angle: pose.headTilt, axis: [0, 0, 1])
    }
    // The keeper faces +z, so its left arm is on +x and lifts by turning about +z, and an arm
    // reaches forward by turning about -x.
    let forward = simd_quatf(angle: -pose.reach, axis: [1, 0, 0])
    set("arm_L") {
      $0.rotation *= forward * simd_quatf(angle: pose.leftArm, axis: [0, 0, 1])
    }
    set("arm_R") {
      $0.rotation *= forward * simd_quatf(angle: -pose.rightArm, axis: [0, 0, 1])
    }
    for eye in ["eye_L", "eye_R"] {
      set(eye) { $0.scale.y *= max(1 - 0.9 * pose.blink, 0.05) }
    }
    set("ear_L") { $0.rotation *= simd_quatf(angle: -pose.ear, axis: [1, 0, 0]) }
    set("ear_R") { $0.rotation *= simd_quatf(angle: -pose.ear * 0.4, axis: [1, 0, 0]) }
    set("tail") { $0.rotation *= simd_quatf(angle: pose.tail, axis: [0, 1, 0]) }
  }

  private func set(_ name: String, _ change: (inout Transform) -> Void) {
    guard let (entity, transform) = rest[name] else { return }
    var posed = transform
    change(&posed)
    entity.transform = posed
  }
}
