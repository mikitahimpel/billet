import Foundation
import simd

/// The orbit camera as plain numbers: where it is, how it coasts, and where it may go.
///
/// The room's walls stand along -x and -z, so yaw stays inside the open quarter, and pitch stays
/// above the floor. Past a limit the camera follows with resistance up to a small overshoot, then
/// eases back. All limits, overshoot included, keep it outside the walls and above the floor.
struct NookiCamera: Equatable {
  static let target: SIMD3<Float> = [0, 0.3, 0]

  static let yawLimits: ClosedRange<Float> = 0.12...1.45
  static let pitchLimits: ClosedRange<Float> = 0.2...1.2
  static let distanceLimits: ClosedRange<Float> = 5.5...11
  static let angleOvershoot: Float = 0.1
  static let distanceOvershoot: Float = 0.5

  private static let resistance: Float = 0.3
  private static let friction: Float = 4
  private static let springRate: Float = 10
  private static let homeRate: Float = 6
  private static let restingSpeed: Float = 0.01
  private static let closeEnough: Float = 0.001

  private static let home = NookiCamera()

  private(set) var yaw: Float = 0.675
  private(set) var pitch: Float = 0.53
  private(set) var distance: Float = 8
  private(set) var yawVelocity: Float = 0
  private(set) var pitchVelocity: Float = 0
  private(set) var isReturningHome = false
  private(set) var lean = SIMD2<Float>.zero
  private var isHeld = false

  var position: SIMD3<Float> {
    let shownYaw = Self.leaned(yaw, by: lean.x, in: Self.yawLimits)
    let shownPitch = Self.leaned(pitch, by: lean.y, in: Self.pitchLimits)
    let flat = cos(shownPitch)
    return Self.target + distance * [flat * sin(shownYaw), sin(shownPitch), flat * cos(shownYaw)]
  }

  /// True when nothing is moving, so the scene can drop to its idle update rate.
  var isAtRest: Bool {
    !isHeld && !isReturningHome && yawVelocity == 0 && pitchVelocity == 0 && isInsideLimits
  }

  private var isInsideLimits: Bool {
    Self.yawLimits.contains(yaw) && Self.pitchLimits.contains(pitch)
      && Self.distanceLimits.contains(distance)
  }

  /// Swings the view from where the orbit put it. The orbit itself does not move, and the view
  /// stays inside the limits, or no further out than an overshoot has taken it.
  mutating func lean(to lean: SIMD2<Float>) {
    self.lean = lean
  }

  /// Follows a drag, in radians. Stops any coasting or trip home.
  mutating func drag(yaw deltaYaw: Float, pitch deltaPitch: Float) {
    hold()
    yaw = Self.resisted(yaw, by: deltaYaw, in: Self.yawLimits, overshoot: Self.angleOvershoot)
    pitch = Self.resisted(
      pitch, by: deltaPitch, in: Self.pitchLimits, overshoot: Self.angleOvershoot)
  }

  /// Follows a pinch step, where a `scale` above 1 moves closer.
  mutating func zoom(by scale: Float) {
    guard scale > 0 else { return }
    hold()
    distance = Self.resisted(
      distance, by: distance / scale - distance, in: Self.distanceLimits,
      overshoot: Self.distanceOvershoot)
  }

  /// Lets go. Velocities are in radians per second, and `coasting` is false for Reduce Motion.
  mutating func release(yawVelocity: Float, pitchVelocity: Float, coasting: Bool) {
    isHeld = false
    self.yawVelocity = coasting ? yawVelocity : 0
    self.pitchVelocity = coasting ? pitchVelocity : 0
    if !coasting { settleLimits() }
  }

  mutating func goHome(animated: Bool) {
    isHeld = false
    yawVelocity = 0
    pitchVelocity = 0
    isReturningHome = animated
    if !animated {
      arriveHome()
    }
  }

  mutating func step(_ delta: Float) {
    guard !isHeld else { return }
    if isReturningHome {
      stepHome(delta)
      return
    }
    yaw += yawVelocity * delta
    pitch += pitchVelocity * delta
    let decay = exp(-Self.friction * delta)
    yawVelocity = Self.resting(yawVelocity * decay)
    pitchVelocity = Self.resting(pitchVelocity * decay)
    springBack(delta)
  }

  private mutating func hold() {
    isHeld = true
    isReturningHome = false
    yawVelocity = 0
    pitchVelocity = 0
  }

  private mutating func stepHome(_ delta: Float) {
    let blend = 1 - exp(-Self.homeRate * delta)
    yaw += (Self.home.yaw - yaw) * blend
    pitch += (Self.home.pitch - pitch) * blend
    distance += (Self.home.distance - distance) * blend
    let gap = max(abs(Self.home.yaw - yaw), abs(Self.home.pitch - pitch))
    if gap < Self.closeEnough, abs(Self.home.distance - distance) < Self.closeEnough * 10 {
      arriveHome()
    }
  }

  private mutating func arriveHome() {
    let lean = lean
    self = Self.home
    self.lean = lean
  }

  private mutating func springBack(_ delta: Float) {
    let blend = 1 - exp(-Self.springRate * delta)
    if !Self.yawLimits.contains(yaw) {
      yawVelocity = 0
      yaw = Self.settled(yaw, in: Self.yawLimits, blend: blend)
    }
    if !Self.pitchLimits.contains(pitch) {
      pitchVelocity = 0
      pitch = Self.settled(pitch, in: Self.pitchLimits, blend: blend)
    }
    if !Self.distanceLimits.contains(distance) {
      distance = Self.settled(distance, in: Self.distanceLimits, blend: blend)
    }
  }

  private mutating func settleLimits() {
    yaw = Self.clamped(yaw, to: Self.yawLimits)
    pitch = Self.clamped(pitch, to: Self.pitchLimits)
    distance = Self.clamped(distance, to: Self.distanceLimits)
  }

  private static func leaned(
    _ value: Float, by lean: Float, in limits: ClosedRange<Float>
  ) -> Float {
    min(max(value + lean, min(limits.lowerBound, value)), max(limits.upperBound, value))
  }

  private static func resisted(
    _ value: Float, by delta: Float, in limits: ClosedRange<Float>, overshoot: Float
  ) -> Float {
    let outward =
      (value >= limits.upperBound && delta > 0) || (value <= limits.lowerBound && delta < 0)
    let moved = value + delta * (outward ? resistance : 1)
    return min(max(moved, limits.lowerBound - overshoot), limits.upperBound + overshoot)
  }

  private static func settled(
    _ value: Float, in limits: ClosedRange<Float>, blend: Float
  ) -> Float {
    let edge = clamped(value, to: limits)
    let next = value + (edge - value) * blend
    return abs(edge - next) < closeEnough ? edge : next
  }

  private static func clamped(_ value: Float, to limits: ClosedRange<Float>) -> Float {
    min(max(value, limits.lowerBound), limits.upperBound)
  }

  private static func resting(_ velocity: Float) -> Float {
    abs(velocity) < restingSpeed ? 0 : velocity
  }
}
