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
  /// How far an opening flight still holds the camera off its place: turn, lift and distance.
  private(set) var flight = SIMD3<Float>(0, 0, 1)
  /// The phone's lean, added to the turn and lift, in radians.
  private(set) var lean = SIMD2<Float>.zero
  private var isHeld = false

  private static let friction: Float = 4
  private static let homeRate: Float = 5
  private static let restingSpeed: Float = 0.005
  /// How far past a limit a drag or a coast may carry the camera before it eases back, so the
  /// view gives at its ends rather than stopping dead.
  static let angleOvershoot: Float = 0.06
  static let zoomOvershoot: Float = 0.05
  /// How much of a drag past a limit the camera follows.
  private static let resistance: Float = 0.3
  /// How quickly the camera eases back inside its limits, per second.
  private static let springRate: Float = 10
  /// How quickly a coast past a limit dies away, per second.
  private static let overshootFriction: Float = 30

  init(home: Home) {
    self.home = home
    yaw = home.yaw
    pitch = home.pitch
  }

  var target: SIMD3<Float> { home.target }

  /// The camera at its home place, keeping only how far the view's shape stands it back: what
  /// the window view's planes are laid out against.
  var atHome: GenzCamera {
    var camera = GenzCamera(home: home)
    camera.standBack = standBack
    return camera
  }
  var fieldOfView: Float { home.fieldOfView }

  var position: SIMD3<Float> {
    let reach = home.distance * zoom * standBack * flight.z
    let shownYaw = yaw + flight.x + lean.x
    let shownPitch = pitch + flight.y + lean.y
    let flat = cos(shownPitch)
    return home.target + reach * SIMD3(flat * sin(shownYaw), sin(shownPitch), flat * cos(shownYaw))
  }

  /// Holds the camera off its place by an opening's turn, lift and distance multiple.
  mutating func fly(yaw: Float, pitch: Float, distance: Float) {
    flight = [yaw, pitch, distance]
  }

  mutating func lean(to lean: SIMD2<Float>) {
    self.lean = lean
  }

  var isAtRest: Bool {
    !isHeld && !isReturningHome && yawVelocity == 0 && pitchVelocity == 0
      && home.yawLimits.contains(yaw) && home.pitchLimits.contains(pitch)
      && home.zoomLimits.contains(zoom)
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
    yaw = Self.resisted(yaw, by: deltaYaw, in: home.yawLimits, overshoot: Self.angleOvershoot)
    pitch = Self.resisted(
      pitch, by: deltaPitch, in: home.pitchLimits, overshoot: Self.angleOvershoot)
  }

  /// Follows a pinch step, where a `scale` above 1 moves closer.
  mutating func zoom(by scale: Float) {
    guard scale > 0 else { return }
    isHeld = true
    isReturningHome = false
    zoom = Self.resisted(
      zoom, by: zoom / scale - zoom, in: home.zoomLimits, overshoot: Self.zoomOvershoot)
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
    (yaw, yawVelocity) = Self.coasted(
      yaw, velocity: yawVelocity, in: home.yawLimits, overshoot: Self.angleOvershoot, delta)
    (pitch, pitchVelocity) = Self.coasted(
      pitch, velocity: pitchVelocity, in: home.pitchLimits, overshoot: Self.angleOvershoot, delta)
    zoom = Self.settled(zoom, in: home.zoomLimits, delta)
  }

  /// A value `velocity` carries for `delta` seconds: slowed by friction, and past a limit slowed
  /// hard while it eases back.
  private static func coasted(
    _ value: Float, velocity: Float, in limits: ClosedRange<Float>, overshoot: Float,
    _ delta: Float
  ) -> (Float, Float) {
    let moved = min(
      max(value + velocity * delta, limits.lowerBound - overshoot), limits.upperBound + overshoot)
    let isOut = !limits.contains(moved)
    let decay = exp(-(isOut ? overshootFriction : friction) * delta)
    var slowed = velocity * decay
    if abs(slowed) < restingSpeed || (isOut && moved != value + velocity * delta) { slowed = 0 }
    // Past a limit the spring pulls back every frame, so the coast turns round in one arc.
    return (settled(moved, in: limits, delta), slowed)
  }

  /// `value` eased back towards `limits` for `delta` seconds, or kept when inside them.
  private static func settled(_ value: Float, in limits: ClosedRange<Float>, _ delta: Float)
    -> Float
  {
    let edge = clamped(value, to: limits)
    guard edge != value else { return value }
    let next = value + (edge - value) * (1 - exp(-springRate * delta))
    return abs(edge - next) < 0.0005 ? edge : next
  }

  /// `value` moved by `delta`, following only part of the way once past a limit, and no further
  /// than `overshoot` beyond it.
  private static func resisted(
    _ value: Float, by delta: Float, in limits: ClosedRange<Float>, overshoot: Float
  ) -> Float {
    let outward =
      (value >= limits.upperBound && delta > 0) || (value <= limits.lowerBound && delta < 0)
    let moved = value + delta * (outward ? resistance : 1)
    return min(max(moved, limits.lowerBound - overshoot), limits.upperBound + overshoot)
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
