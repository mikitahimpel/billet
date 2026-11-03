import Foundation
import PetScene
import simd

/// Where everything stands on the first-launch windowsill, in room units (``GenzRoomPoint``): a
/// deep sill under a night window, candles at both ends, fairy lights down the sides of the
/// window, and the heart floating over a cushion in the middle.
enum OnboardingLayout {
  static let width: Float = 6
  static let height: Float = 10
  static let wall: Float = 0.3

  static let sillTop: Float = 2.45
  static let sill = (x0: Float(0), x1: Float(6), y0: Float(0), y1: Float(2.8))
  static let window = (x0: Float(1.0), x1: Float(5.0), z0: Float(3.6), z1: Float(8.4))

  /// Where the middle of the heart floats, and how tall it is.
  static let heart = GenzRoomPoint(3.0, 1.45, 4.45)
  static let heartHeight: Float = 2.5
  static let cushion = GenzRoomPoint(3.0, 1.45, sillTop)

  /// Each candle: where it stands on the sill, its radius and its height.
  static let candles: [(spot: GenzRoomPoint, radius: Float, height: Float)] = [
    (GenzRoomPoint(0.85, 1.55, sillTop), 0.3, 1.3),
    (GenzRoomPoint(1.55, 0.85, sillTop), 0.24, 2.05),
    (GenzRoomPoint(4.55, 1.7, sillTop), 0.32, 0.85),
    (GenzRoomPoint(5.2, 0.95, sillTop), 0.22, 1.55),
  ]

  /// The fairy lights: a strand hanging down each side of the window, bellying out a little,
  /// from below its top to the sill. They stay off the top of the window, where the words are.
  static let strands: [[GenzRoomPoint]] = [Float(0.5), Float(5.5)].map { x in
    let out: Float = x < 3 ? -1 : 1
    return (0..<7).map { index in
      let along = Float(index) / 6
      return GenzRoomPoint(x + out * 0.12 * sin(along * .pi), 0.4, 6.9 - along * 3.9)
    }
  }

  /// Every fairy light, the left strand top to bottom and then the right.
  static let beads: [GenzRoomPoint] = strands.flatMap { $0 }

  /// The stars and the moon in the window, as points on its glass and sizes.
  static let stars: [(x: Float, z: Float, size: Float)] = [
    (1.5, 7.7, 0.07), (2.3, 8.0, 0.05), (3.6, 7.4, 0.06), (1.9, 6.6, 0.04), (4.3, 6.4, 0.05),
    (2.7, 5.6, 0.04), (1.3, 4.6, 0.05), (4.6, 4.9, 0.04),
  ]
  static let moon = (x: Float(4.15), z: Float(7.55), radius: Float(0.34))

  static let camera = GenzCamera.Home(
    target: GenzRoomPoint(3.0, 1.3, 4.25).scene, yaw: 0, pitch: 0.15, distance: 17.5,
    fieldOfView: 40, yawLimits: -0.12...0.12, pitchLimits: 0.08...0.26)
}

/// The first launch's flight, as values of the time since it began: the camera glides in out of
/// the dark, the candles light one by one, then the fairy lights run along the window, then the
/// heart warms up. With motion reduced nothing flies: the scene fades up from the dark at its
/// place, everything at once.
struct OnboardingTimeline: Equatable {
  /// Seconds the flight takes.
  static let length = 5.2
  /// Seconds the fade takes with motion reduced.
  static let calmLength = 1.6

  var reduceMotion: Bool

  var duration: Double { reduceMotion ? Self.calmLength : Self.length }

  /// How far the camera still is from its place: 1 at the start, 0 once arrived.
  func away(_ time: Double) -> Float {
    reduceMotion ? 0 : 1 - Float(Self.smoother(time / Self.length))
  }

  /// How much of the view the dark still covers.
  func darkness(_ time: Double) -> Double {
    reduceMotion
      ? 1 - Self.smoother(time / Self.calmLength)
      : 1 - Self.smoother((time - 0.15) / 2.3)
  }

  /// How far candle `index` has caught, from 0 (unlit) to 1.
  func candle(_ index: Int, _ time: Double) -> Float {
    fade(time, from: 0.9 + 0.5 * Double(index), length: 0.45)
  }

  /// How far fairy light `index` of `count` has come on: they run along the window.
  func bead(_ index: Int, of count: Int, _ time: Double) -> Float {
    let along = count > 1 ? Double(index) / Double(count - 1) : 0
    return fade(time, from: 2.7 + along * 0.9, length: 0.3)
  }

  /// How far the heart's own glow has come up.
  func heartGlow(_ time: Double) -> Float {
    fade(time, from: 3.0, length: 1.4)
  }

  /// How bright the scene's lights are, from a faint start to full.
  func warmth(_ time: Double) -> Float {
    0.12 + 0.88 * fade(time, from: 0.6, length: 3.4)
  }

  private func fade(_ time: Double, from start: Double, length: Double) -> Float {
    if reduceMotion { return Float(Self.smoother(time / Self.calmLength)) }
    return Float(Self.smoother((time - start) / length))
  }

  /// 0 below 0, 1 above 1, and an S-curve with flat ends between.
  static func smoother(_ value: Double) -> Double {
    let x = min(max(value, 0), 1)
    return x * x * x * (x * (x * 6 - 15) + 10)
  }
}

/// The heart's beat and float at rest, as values of the time: a soft lub-dub that swells it a
/// little, and a slow bob and sway.
enum HeartMotion {
  /// Seconds from one beat to the next.
  static let period = 1.3

  /// How far the heart is swollen by its beat, from 0 to about 1.
  static func beat(_ time: Double) -> Float {
    let phase = time.truncatingRemainder(dividingBy: period)
    func pulse(at centre: Double, width: Double) -> Double {
      exp(-pow((phase - centre) / width, 2))
    }
    return Float(pulse(at: 0.12, width: 0.07) + 0.6 * pulse(at: 0.36, width: 0.08))
  }

  /// The heart's scale for a swell: wider and deeper a touch more than taller, so it reads as
  /// soft.
  static func scale(swell: Float) -> SIMD3<Float> {
    [1 + 0.055 * swell, 1 + 0.04 * swell, 1 + 0.07 * swell]
  }

  /// The squish after a tap, `age` seconds ago: a quick squash that wobbles back.
  static func squish(_ age: Double) -> SIMD3<Float> {
    guard age >= 0, age < 0.9 else { return .one }
    let wobble = Float(sin(age * 18) * exp(-age * 5.5))
    return [1 + 0.12 * wobble, 1 - 0.14 * wobble, 1 + 0.1 * wobble]
  }

  /// How high the heart bobs over its place, in room units.
  static func bob(_ time: Double) -> Float {
    Float(sin(time * 1.25)) * 0.13
  }

  /// How far it turns about the vertical and leans, in radians.
  static func sway(_ time: Double) -> (yaw: Float, roll: Float) {
    (Float(sin(time * 0.55)) * 0.2, Float(sin(time * 0.9 + 0.7)) * 0.045)
  }
}

/// Where the two halves of the heart are, each eased towards where the moment wants it: together,
/// opened with this phone's half forward and the partner's waiting on its side, or the partner's
/// gone until it flies in. Offsets are in room units from the heart's middle, x to the viewer's
/// right, y up and z towards the viewer. With motion reduced nothing travels: each half is at its
/// place at once and fades in or out there.
struct HeartHalves: Equatable {
  struct Pose: Equatable {
    var offset: SIMD3<Float>
    var opacity: Float
    /// How far the half leans out, about the axis towards the viewer.
    var tilt: Float

    static let home = Pose(offset: .zero, opacity: 1, tilt: 0)
  }

  private(set) var mine: HeartSide
  private(set) var me = Pose.home
  private(set) var partner = Pose.home
  /// True once the halves have met in `together`, until the heart opens again.
  private(set) var hasMet = true

  /// How fast each half closes on its place, per second.
  static let rate: Float = 2.4
  static let fadeRate: Float = 3.2
  /// How close the partner's half must come to count as met.
  static let meeting: Float = 0.05

  init(mine: HeartSide = .left) {
    self.mine = mine
  }

  /// Where each half wants to be in `moment`, for this phone's `mine`.
  static func targets(_ moment: OnboardingSceneState.Moment, mine: HeartSide) -> (
    me: Pose, partner: Pose
  ) {
    let out: Float = mine == .left ? -1 : 1
    let opened = Pose(offset: [out * 0.95, -0.08, 0.3], opacity: 1, tilt: -out * 0.14)
    switch moment {
    case .arriving, .resting, .together:
      return (.home, .home)
    case .apart(.waiting):
      return (opened, Pose(offset: [-out * 1.4, 0.4, -0.35], opacity: 0.42, tilt: out * 0.2))
    case .apart(.away):
      return (opened, Pose(offset: [-out * 7, 3.2, -2.5], opacity: 0, tilt: out * 0.8))
    }
  }

  /// Moves `delta` seconds towards `moment`. Returns true on the step the partner's half meets
  /// this one.
  mutating func step(
    _ delta: Double, towards moment: OnboardingSceneState.Moment, mine: HeartSide,
    reduceMotion: Bool
  ) -> Bool {
    if mine != self.mine {
      self.mine = mine
    }
    let target = Self.targets(moment, mine: mine)
    let move = 1 - exp(-Self.rate * Float(delta))
    let fade = 1 - exp(-Self.fadeRate * Float(delta))
    for (pose, wanted) in [(\HeartHalves.me, target.me), (\HeartHalves.partner, target.partner)] {
      var current = self[keyPath: pose]
      if reduceMotion {
        current.offset = wanted.offset
        current.tilt = wanted.tilt
      } else {
        current.offset += (wanted.offset - current.offset) * move
        current.tilt += (wanted.tilt - current.tilt) * move
      }
      current.opacity += (wanted.opacity - current.opacity) * fade
      self[keyPath: pose] = current
    }
    guard moment == .together else {
      if case .apart = moment { hasMet = false }
      return false
    }
    let met =
      reduceMotion
      ? partner.opacity > 0.95
      : simd_length(partner.offset) < Self.meeting && simd_length(me.offset) < Self.meeting
    guard met, !hasMet else { return false }
    hasMet = true
    return true
  }

  /// Puts both halves at their places for `moment` at once, as when the scene opens there.
  mutating func settle(_ moment: OnboardingSceneState.Moment, mine: HeartSide) {
    self.mine = mine
    let target = Self.targets(moment, mine: mine)
    me = target.me
    partner = target.partner
    hasMet = true
  }
}

extension OnboardingLayout {
  /// The paper tag with the pair's code, leaning back against the front of the cushion: where its
  /// bottom edge stands, its size, its turn and how far back it leans.
  static let tag = (
    foot: GenzRoomPoint(3.0, 2.55, sillTop + 0.02), width: Float(2.5), height: Float(1.2),
    yaw: Float(0.06), lean: Float(0.32)
  )
}

/// The burst of warm light as the halves meet: a flash that spreads and fades.
enum OnboardingBurst {
  /// Seconds it lasts.
  static let length = 1.6

  /// How strong it is `age` seconds in: up fast, then a long fall.
  static func strength(_ age: Double) -> Double {
    guard age >= 0, age < length else { return 0 }
    let rise = min(age / 0.12, 1)
    let fall = 1 - TimelineEase.smoother((age - 0.12) / (length - 0.12))
    return rise * fall
  }

  /// How far out it has spread `age` seconds in, in room units.
  static func spread(_ age: Double) -> Double {
    1.5 + 7.5 * TimelineEase.smoother(age / length)
  }
}

enum TimelineEase {
  static func smoother(_ value: Double) -> Double { OnboardingTimeline.smoother(value) }
}
