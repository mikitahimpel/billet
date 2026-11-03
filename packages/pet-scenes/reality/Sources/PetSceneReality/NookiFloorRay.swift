import Foundation
import simd

/// Where a moved piece stands on the floor, and how it is turned.
struct NookiSpot: Codable, Hashable, Sendable {
  var x: Float
  var z: Float
  var yaw: Float
}

/// Where a point on screen falls on the floor.
enum NookiFloorRay {
  /// The floor point under `point`, or nil if that ray never reaches the floor. The field of view
  /// is the camera's vertical one.
  static func floorPoint(
    under point: SIMD2<Float>, viewSize: SIMD2<Float>, camera: SIMD3<Float>, target: SIMD3<Float>,
    verticalFieldOfView degrees: Float, height: Float = 0
  ) -> SIMD2<Float>? {
    let ray = direction(
      under: point, viewSize: viewSize, camera: camera, target: target,
      verticalFieldOfView: degrees)
    guard ray.y < 0 else { return nil }
    let landing = camera + ray * ((height - camera.y) / ray.y)
    return SIMD2(landing.x, landing.z)
  }

  /// The direction from the camera through `point`, not normalised.
  static func direction(
    under point: SIMD2<Float>, viewSize: SIMD2<Float>, camera: SIMD3<Float>, target: SIMD3<Float>,
    verticalFieldOfView degrees: Float
  ) -> SIMD3<Float> {
    let forward = simd_normalize(target - camera)
    let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
    let up = simd_cross(right, forward)
    let reach = tan(degrees * .pi / 360)
    let across = (point.x / viewSize.x * 2 - 1) * reach * viewSize.x / viewSize.y
    let down = (1 - point.y / viewSize.y * 2) * reach
    return forward + right * across + up * down
  }
}
