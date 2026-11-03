import Foundation
import simd

/// Where everything stands on the first-launch windowsill, in room units (``GenzRoomPoint``): a
/// deep sill under a night window, candles at both ends, fairy lights along the top of the
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

  /// The fairy lights strung along the top of the window, sagging in the middle.
  static let beads: [GenzRoomPoint] = (0..<15).map { index in
    let along = Float(index) / 14
    return GenzRoomPoint(0.55 + along * 4.9, 0.4, 8.95 - 0.75 * sin(along * .pi))
  }

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
