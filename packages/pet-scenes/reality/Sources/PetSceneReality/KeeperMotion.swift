import Foundation
import simd

/// How the shopkeeper holds itself in one frame. Angles are in radians.
struct KeeperPose: Equatable {
  /// How far the body rises off the floor, in model units.
  var hop: Float = 0
  /// The chest's swell, as a share of its height.
  var breath: Float = 0
  /// The body's lean to the side.
  var sway: Float = 0
  /// Turn to its left (positive) or right, lift up (positive) or down, and tilt of the head.
  var headYaw: Float = 0
  var headPitch: Float = 0
  var headTilt: Float = 0
  /// How far each arm is lifted out to the side, from hanging (0).
  var leftArm: Float = KeeperMotion.restingArm
  var rightArm: Float = KeeperMotion.restingArm
  /// 0 with the eyes open, 1 shut.
  var blink: Float = 0
  var tail: Float = 0
  var ear: Float = 0
}

/// The shopkeeper's life behind the counter as plain numbers: breathing, blinking, a tail that
/// sways, eyes that follow you, a glance at what you tapped, a wave hello and a little cheer when
/// you buy something.
struct KeeperMotion {
  enum Gesture: Equatable {
    case wave
    case cheer
  }

  static let restingArm: Float = 0.12
  static let waveLength = 2.1
  static let cheerLength = 1.5
  static let glanceLength = 1.6
  /// How far the head turns or lifts at most to follow you, so it never looks over its shoulder.
  static let headYawLimit: Float = 0.75
  static let headPitchLimit: Float = 0.4
  private static let followRate: Float = 6

  private(set) var time = 0.0
  private(set) var gesture: (kind: Gesture, start: Double)?
  private var glance: (yaw: Float, pitch: Float, until: Double)?
  private var nextBlink = 1.4
  private var nextTwitch = 5.0
  private var yaw: Float = 0
  private var pitch: Float = 0
  private var random: SplitMix

  init(seed: UInt64) {
    random = SplitMix(seed: seed)
  }

  var isBusy: Bool { gesture != nil }

  mutating func wave() {
    guard gesture == nil else { return }
    gesture = (.wave, time)
  }

  /// A cheer cuts in on anything, since it answers a purchase.
  mutating func cheer() {
    gesture = (.cheer, time)
  }

  /// Turns to look at something for a moment, at `yaw` and `pitch` from straight ahead.
  mutating func glance(yaw: Float, pitch: Float) {
    glance = (yaw, pitch, time + Self.glanceLength)
  }

  /// Steps `delta` seconds on, with the viewer at `viewer` (yaw, pitch) from the keeper's face.
  /// With `still`, as when motion is reduced, only the eyes follow and nothing bounces.
  mutating func step(_ delta: Double, viewer: SIMD2<Float>, still: Bool = false) -> KeeperPose {
    time += delta
    var pose = KeeperPose()
    let t = Float(time)
    if !still {
      pose.breath = 0.014 * sin(t * 2 * .pi / 3.4)
      pose.sway = 0.025 * sin(t * 2 * .pi / 6.1)
      pose.tail = 0.22 * sin(t * 2 * .pi / 2.7)
      pose.headTilt = 0.05 * sin(t * 2 * .pi / 7.3)
    }

    var target = SIMD2(
      Self.clamped(viewer.x, Self.headYawLimit), Self.clamped(viewer.y, Self.headPitchLimit))
    if let glance, time < glance.until {
      target = SIMD2(glance.yaw, glance.pitch)
    } else {
      glance = nil
    }
    let blend = 1 - exp(-Self.followRate * Float(delta))
    yaw += (target.x - yaw) * blend
    pitch += (target.y - pitch) * blend
    pose.headYaw = yaw
    pose.headPitch = pitch

    pose.blink = blinkAmount()
    pose.ear = earTwitch()

    if let gesture {
      let age = time - gesture.start
      switch gesture.kind {
      case .wave:
        if age >= Self.waveLength {
          self.gesture = nil
        } else {
          let lift = Self.envelope(age, rise: 0.35, fall: 0.4, length: Self.waveLength)
          let swing = still ? 0 : 0.38 * sin(Float(age - 0.35) * 2 * .pi * 2.6)
          pose.rightArm = Self.restingArm + lift * (2.45 - Self.restingArm) + lift * swing
          pose.headTilt += lift * 0.14
        }
      case .cheer:
        if age >= Self.cheerLength {
          self.gesture = nil
        } else {
          let lift = Self.envelope(age, rise: 0.25, fall: 0.35, length: Self.cheerLength)
          pose.leftArm = Self.restingArm + lift * (2.2 - Self.restingArm)
          pose.rightArm = pose.leftArm
          pose.blink = max(pose.blink, lift * 0.85)
          if !still, age < 1.0 {
            pose.hop = 0.09 * abs(sin(Float(age) * .pi * 2))
          }
          pose.headPitch += lift * 0.15
        }
      }
    }
    return pose
  }

  private mutating func blinkAmount() -> Float {
    let closing = 0.07
    let shut = 0.05
    let opening = 0.1
    let age = time - nextBlink
    if age > closing + shut + opening {
      nextBlink = time + 2.2 + random.unit() * 3.6
      return 0
    }
    guard age >= 0 else { return 0 }
    if age < closing { return Float(age / closing) }
    if age < closing + shut { return 1 }
    return Float(1 - (age - closing - shut) / opening)
  }

  private mutating func earTwitch() -> Float {
    let age = time - nextTwitch
    if age > 0.3 {
      nextTwitch = time + 4 + random.unit() * 7
      return 0
    }
    guard age >= 0 else { return 0 }
    return 0.35 * sin(Float(age / 0.3) * .pi)
  }

  /// 0 to 1 over `rise` seconds, held, and back to 0 over the last `fall` seconds of `length`.
  static func envelope(_ age: Double, rise: Double, fall: Double, length: Double) -> Float {
    let up = min(max(age / rise, 0), 1)
    let down = min(max((length - age) / fall, 0), 1)
    let share = min(up, down)
    return Float(share * share * (3 - 2 * share))
  }

  /// The turn and lift that points the face, looking along +z, at `offset` from the head.
  static func aim(at offset: SIMD3<Float>) -> SIMD2<Float> {
    let flat = (offset.x * offset.x + offset.z * offset.z).squareRoot()
    return SIMD2(atan2(offset.x, offset.z), atan2(offset.y, max(flat, 0.0001)))
  }

  private static func clamped(_ value: Float, _ limit: Float) -> Float {
    min(max(value, -limit), limit)
  }
}

/// A small seeded random source, so a keeper's blinks are not all in step and tests repeat.
struct SplitMix {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// A number from 0 up to 1.
  mutating func unit() -> Double {
    Double(next() >> 11) / Double(1 << 53)
  }
}
