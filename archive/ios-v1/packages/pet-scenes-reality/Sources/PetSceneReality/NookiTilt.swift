import Foundation
import simd

#if os(iOS)
  import CoreMotion
#endif

/// How the phone is leaning, as plain numbers.
///
/// Only a change of pose counts: the pose the phone is held in fades into a baseline over several
/// seconds, so holding it at any angle reads as level. The lean is smoothed, ignores sensor noise
/// and flattens out softly at `reach`.
struct NookiTilt: Equatable {
  /// The most the view may swing either way, in radians.
  static let reach: Float = 0.14

  private static let gain: Float = 0.8
  private static let smoothingRate: Float = 7
  private static let baselineRate: Float = 0.12
  private static let settleRate: Float = 5
  private static let noise: Float = 0.012
  private static let stillSpeed: Float = 0.002

  /// Sideways and forward swing in radians, for the view.
  private(set) var lean = SIMD2<Float>.zero
  /// The change of pose in units of gravity, before any softening.
  private(set) var pull = SIMD2<Float>.zero
  private(set) var isMoving = false
  private var baseline: SIMD2<Float>?

  /// Takes a reading of the gravity vector in device coordinates.
  mutating func update(gravity: SIMD3<Float>, delta: Float) {
    let pose = SIMD2(gravity.x, gravity.z)
    let held = baseline ?? pose
    baseline = held + (pose - held) * Self.blend(Self.baselineRate, delta)
    let change = pose - held
    pull = SIMD2(Self.quieted(change.x), Self.quieted(change.y))
    let goal = Self.reach * tanhVector(pull * Self.gain / Self.reach)
    move(toward: goal, rate: Self.smoothingRate, delta: delta)
  }

  /// Eases back to level when there is no reading to follow.
  mutating func settle(delta: Float) {
    baseline = nil
    pull = .zero
    move(toward: .zero, rate: Self.settleRate, delta: delta)
  }

  private mutating func move(toward goal: SIMD2<Float>, rate: Float, delta: Float) {
    let previous = lean
    lean += (goal - lean) * Self.blend(rate, delta)
    if simd_length(lean - goal) < Self.stillSpeed * 0.1 { lean = goal }
    isMoving = delta > 0 && simd_length(lean - previous) / delta > Self.stillSpeed
  }

  private func tanhVector(_ value: SIMD2<Float>) -> SIMD2<Float> {
    SIMD2(tanh(value.x), tanh(value.y))
  }

  private static func blend(_ rate: Float, _ delta: Float) -> Float {
    1 - exp(-rate * delta)
  }

  private static func quieted(_ value: Float) -> Float {
    abs(value) < noise ? 0 : value - copysign(noise, value)
  }
}

/// Somewhere to read the gravity vector from. Runs only between `start` and `stop`.
@MainActor protocol NookiTiltSource: AnyObject {
  /// Gravity in device coordinates, in units of g, or nil when there is no reading.
  var gravity: SIMD3<Float>? { get }
  func start()
  func stop()
}

@MainActor enum NookiTiltSources {
  /// The phone's own sensors, or the scripted stand-in on the Simulator, which has none.
  static func standard() -> any NookiTiltSource {
    #if os(iOS) && !targetEnvironment(simulator)
      DeviceTiltSource()
    #else
      ScriptedTiltSource(script: .fromLaunchArguments())
    #endif
  }
}

#if os(iOS) && !targetEnvironment(simulator)
  /// Polled once a frame: no queue and no callbacks, and nothing runs once stopped.
  @MainActor private final class DeviceTiltSource: NookiTiltSource {
    private let manager = CMMotionManager()

    var gravity: SIMD3<Float>? {
      manager.deviceMotion.map {
        SIMD3(Float($0.gravity.x), Float($0.gravity.y), Float($0.gravity.z))
      }
    }

    func start() {
      guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
      manager.deviceMotionUpdateInterval = 1.0 / 30
      manager.startDeviceMotionUpdates()
    }

    func stop() {
      manager.stopDeviceMotionUpdates()
    }
  }
#endif

/// Tilt for a machine with no sensors, for exercising the scene by hand.
///
/// `-nookiTilt sweep` leans slowly around a circle. `-nookiTiltFile <path>` reads two numbers,
/// sideways and forward in units of g, each time the scene asks, so a script can lean the phone.
@MainActor final class ScriptedTiltSource: NookiTiltSource {
  enum Script: Equatable {
    case none
    case sweep
    case file(String)

    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> Script {
      if let path = defaults.string(forKey: "nookiTiltFile") { return .file(path) }
      return defaults.string(forKey: "nookiTilt") == "sweep" ? .sweep : .none
    }
  }

  private let script: Script
  private let now: () -> TimeInterval
  private var startedAt: TimeInterval?

  init(
    script: Script, now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
  ) {
    self.script = script
    self.now = now
  }

  var gravity: SIMD3<Float>? {
    guard let startedAt else { return nil }
    switch script {
    case .none:
      return nil
    case .sweep:
      let angle = Float(now() - startedAt) * 0.9
      return Self.leaning(SIMD2(sin(angle), cos(angle) - 1) * 0.2)
    case .file(let path):
      return (try? String(contentsOfFile: path, encoding: .utf8)).flatMap(Self.parsed)
    }
  }

  func start() { startedAt = now() }
  func stop() { startedAt = nil }

  static func parsed(_ text: String) -> SIMD3<Float>? {
    let numbers = text.split(whereSeparator: \.isWhitespace).compactMap { Float($0) }
    guard numbers.count == 2 else { return nil }
    return leaning(SIMD2(numbers[0], numbers[1]))
  }

  private static func leaning(_ pull: SIMD2<Float>) -> SIMD3<Float> {
    SIMD3(pull.x, -0.7, pull.y - 0.7)
  }
}
