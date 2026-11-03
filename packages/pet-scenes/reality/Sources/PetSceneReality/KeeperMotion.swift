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
  /// The body's bow forward, as in a greeting.
  var bow: Float = 0
  /// Turn to its left (positive) or right, lift up (positive) or down, and tilt of the head.
  var headYaw: Float = 0
  var headPitch: Float = 0
  var headTilt: Float = 0
  /// How far each arm is lifted out to the side, from hanging (0).
  var leftArm: Float = KeeperMotion.restingArm
  var rightArm: Float = KeeperMotion.restingArm
  /// How far both arms reach forward, from hanging (0), as when handing something over.
  var reach: Float = 0
  /// 0 with the eyes open, 1 shut.
  var blink: Float = 0
  var tail: Float = 0
  var ear: Float = 0
}

/// The shopkeeper's life behind the counter as plain numbers, the same for every keeper: an idle of
/// breathing, blinking, a tail that sways and eyes that follow you; a greeting bow when you come
/// in, then a sweep of the arms to the shelves; a glance at what you tapped; a wave; handing over
/// what you bought, then a little cheer.
struct KeeperMotion {
  enum Gesture: Equatable {
    case greet
    case present
    case wave
    case handOver
    case cheer

    var length: Double {
      switch self {
      case .greet: KeeperMotion.greetLength
      case .present: KeeperMotion.presentLength
      case .wave: KeeperMotion.waveLength
      case .handOver: KeeperMotion.handOverLength
      case .cheer: KeeperMotion.cheerLength
      }
    }
  }

  static let restingArm: Float = 0.12
  static let greetLength = 1.3
  static let presentLength = 2.6
  static let waveLength = 2.1
  static let handOverLength = 2.0
  static let cheerLength = 1.5
  static let glanceLength = 1.6
  /// How far the head turns or lifts at most to follow you, so it never looks over its shoulder.
  static let headYawLimit: Float = 0.75
  static let headPitchLimit: Float = 0.4
  private static let followRate: Float = 6

  private(set) var time = 0.0
  private(set) var gesture: (kind: Gesture, start: Double)?
  /// What follows the gesture now playing, in order.
  private(set) var queue: [Gesture] = []
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

  /// How far into a hand-over the keeper is, from 0 to 1, or `nil` when it is not handing over.
  var handOverProgress: Double? {
    guard let gesture, gesture.kind == .handOver else { return nil }
    return min(max((time - gesture.start) / Self.handOverLength, 0), 1)
  }

  mutating func wave() {
    guard gesture == nil else { return }
    gesture = (.wave, time)
  }

  /// A bow hello, then a sweep of the arms to what is for sale, as when you come in.
  mutating func welcome() {
    gesture = (.greet, time)
    queue = [.present]
  }

  /// Hands over what you bought, then cheers. It cuts in on anything, since it answers a purchase.
  mutating func handOver() {
    gesture = (.handOver, time)
    queue = [.cheer]
  }

  /// A cheer cuts in on anything, since it answers a purchase.
  mutating func cheer() {
    gesture = (.cheer, time)
    queue = []
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
      if age >= gesture.kind.length {
        self.gesture = queue.isEmpty ? nil : (queue.removeFirst(), time)
      } else {
        pose = Self.perform(gesture.kind, age: age, on: pose, still: still)
      }
    }
    return pose
  }

  /// `pose` with `gesture` laid over it, `age` seconds in.
  private static func perform(_ gesture: Gesture, age: Double, on base: KeeperPose, still: Bool)
    -> KeeperPose
  {
    var pose = base
    let length = gesture.length
    switch gesture {
    case .greet:
      let lift = envelope(age, rise: 0.35, fall: 0.45, length: length)
      pose.bow = lift * 0.32
      pose.headPitch -= lift * 0.3
      pose.headTilt += lift * 0.1
      pose.leftArm = restingArm + lift * 0.25
      pose.rightArm = pose.leftArm
    case .present:
      // Its left arm out to the shelves on its left, then its right to the other side, the head
      // following each, palms open.
      let half = length / 2
      let first = envelope(age, rise: 0.3, fall: 0.3, length: half)
      let second = envelope(age - half, rise: 0.3, fall: 0.3, length: half)
      pose.leftArm = restingArm + first * (1.35 - restingArm)
      pose.rightArm = restingArm + second * (1.35 - restingArm)
      pose.reach = (first + second) * 0.35
      pose.headYaw += (first - second) * 0.55
      pose.headPitch += (first + second) * 0.1
    case .wave:
      let lift = envelope(age, rise: 0.35, fall: 0.4, length: length)
      let swing = still ? 0 : 0.38 * sin(Float(age - 0.35) * 2 * .pi * 2.6)
      pose.rightArm = restingArm + lift * (2.45 - restingArm) + lift * swing
      pose.headTilt += lift * 0.14
    case .handOver:
      let lift = envelope(age, rise: 0.45, fall: 0.5, length: length)
      pose.reach = lift * 1.25
      pose.leftArm = restingArm + lift * 0.18
      pose.rightArm = pose.leftArm
      pose.bow = lift * 0.14
      pose.headPitch -= lift * 0.12
      pose.headTilt += lift * 0.08
    case .cheer:
      let lift = envelope(age, rise: 0.25, fall: 0.35, length: length)
      pose.leftArm = restingArm + lift * (2.2 - restingArm)
      pose.rightArm = pose.leftArm
      pose.blink = max(pose.blink, lift * 0.85)
      if !still, age < 1.0 {
        pose.hop = 0.09 * abs(sin(Float(age) * .pi * 2))
      }
      pose.headPitch += lift * 0.15
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
