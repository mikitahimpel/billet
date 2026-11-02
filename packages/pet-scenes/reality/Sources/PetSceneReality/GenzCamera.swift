import CoreGraphics
import Foundation
import simd

/// The camera of a styled room as plain numbers: an orbit around `target` that starts close, at
/// the mockup's angle, and can be pinched out until the room reads as a diorama again.
struct GenzCamera: Equatable {
  struct Home: Equatable {
    var target: SIMD3<Float>
    var yaw: Float
    var pitch: Float
    var distance: Float
    /// Vertical field of view, in degrees.
    var fieldOfView: Float
    /// Width over height of the view the home distance is set for.
    var aspect: Float = 393.0 / 852.0
    var yawLimits: ClosedRange<Float>
    var pitchLimits: ClosedRange<Float>
    /// How far a pinch may take the camera, as multiples of the home distance.
    var zoomLimits: ClosedRange<Float> = 0.85...2.2
  }

  let home: Home
  private(set) var yaw: Float
  private(set) var pitch: Float
  private(set) var zoom: Float = 1
  private(set) var yawVelocity: Float = 0
  private(set) var pitchVelocity: Float = 0
  private(set) var isReturningHome = false
  /// How much further out the view's shape puts the camera, so a narrow view still shows the room.
  private(set) var standBack: Float = 1
  private var isHeld = false

  private static let friction: Float = 4
  private static let homeRate: Float = 5
  private static let restingSpeed: Float = 0.005

  init(home: Home) {
    self.home = home
    yaw = home.yaw
    pitch = home.pitch
  }

  var target: SIMD3<Float> { home.target }
  var fieldOfView: Float { home.fieldOfView }

  var position: SIMD3<Float> {
    let reach = home.distance * zoom * standBack
    let flat = cos(pitch)
    return home.target + reach * SIMD3(flat * sin(yaw), sin(pitch), flat * cos(yaw))
  }

  var isAtRest: Bool {
    !isHeld && !isReturningHome && yawVelocity == 0 && pitchVelocity == 0
  }

  /// How far the view has turned from home, from -1 to 1 across the yaw limits.
  var turn: Float {
    let span = max(home.yawLimits.upperBound - home.yawLimits.lowerBound, 0.001)
    return (yaw - home.yaw) / span * 2
  }

  mutating func fit(to size: SIMD2<Float>) {
    guard size.x > 0, size.y > 0 else { return }
    standBack = max(0.7, home.aspect * size.y / size.x)
  }

  /// Follows a drag, in radians.
  mutating func drag(yaw deltaYaw: Float, pitch deltaPitch: Float) {
    isHeld = true
    isReturningHome = false
    yawVelocity = 0
    pitchVelocity = 0
    yaw = Self.clamped(yaw + deltaYaw, to: home.yawLimits)
    pitch = Self.clamped(pitch + deltaPitch, to: home.pitchLimits)
  }

  /// Follows a pinch step, where a `scale` above 1 moves closer.
  mutating func zoom(by scale: Float) {
    guard scale > 0 else { return }
    isHeld = true
    isReturningHome = false
    zoom = Self.clamped(zoom / scale, to: home.zoomLimits)
  }

  mutating func release(yawVelocity: Float, pitchVelocity: Float, coasting: Bool) {
    isHeld = false
    self.yawVelocity = coasting ? yawVelocity : 0
    self.pitchVelocity = coasting ? pitchVelocity : 0
  }

  mutating func goHome(animated: Bool) {
    isHeld = false
    yawVelocity = 0
    pitchVelocity = 0
    isReturningHome = animated
    if !animated {
      yaw = home.yaw
      pitch = home.pitch
      zoom = 1
    }
  }

  mutating func step(_ delta: Float) {
    guard !isHeld else { return }
    if isReturningHome {
      let blend = 1 - exp(-Self.homeRate * delta)
      yaw += (home.yaw - yaw) * blend
      pitch += (home.pitch - pitch) * blend
      zoom += (1 - zoom) * blend
      if abs(home.yaw - yaw) + abs(home.pitch - pitch) + abs(1 - zoom) < 0.002 {
        goHome(animated: false)
      }
      return
    }
    yaw = Self.clamped(yaw + yawVelocity * delta, to: home.yawLimits)
    pitch = Self.clamped(pitch + pitchVelocity * delta, to: home.pitchLimits)
    let decay = exp(-Self.friction * delta)
    yawVelocity = abs(yawVelocity * decay) < Self.restingSpeed ? 0 : yawVelocity * decay
    pitchVelocity = abs(pitchVelocity * decay) < Self.restingSpeed ? 0 : pitchVelocity * decay
  }

  /// Where `point` lands in a view of `size` points, or `nil` when it is behind the camera.
  func project(_ point: SIMD3<Float>, in size: CGSize) -> CGPoint? {
    Self.project(
      point, from: position, towards: home.target, fieldOfView: home.fieldOfView, in: size)
  }

  static func project(
    _ point: SIMD3<Float>, from eye: SIMD3<Float>, towards target: SIMD3<Float>,
    fieldOfView: Float, in size: CGSize
  ) -> CGPoint? {
    guard size.width > 0, size.height > 0 else { return nil }
    let forward = simd_normalize(target - eye)
    let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
    let up = simd_cross(right, forward)
    let offset = point - eye
    let depth = simd_dot(offset, forward)
    guard depth > 0.001 else { return nil }
    let halfHeight = tan(fieldOfView * .pi / 360) * depth
    let aspect = Float(size.width / size.height)
    let x = simd_dot(offset, right) / (halfHeight * aspect)
    let y = simd_dot(offset, up) / halfHeight
    return CGPoint(
      x: CGFloat((x + 1) / 2) * size.width, y: CGFloat((1 - y) / 2) * size.height)
  }

  private static func clamped(_ value: Float, to limits: ClosedRange<Float>) -> Float {
    min(max(value, limits.lowerBound), limits.upperBound)
  }
}
