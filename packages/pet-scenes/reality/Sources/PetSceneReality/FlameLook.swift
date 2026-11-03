import Foundation
import Pet
import PetScene
import simd

/// Where everything stands on the flame's windowsill, in room units (``GenzRoomPoint``). It is the
/// first-launch sill, so the two scenes read as the same window: a deep sill under a night window
/// that shows the room's own view.
enum FlameLayout {
  static let sillTop = OnboardingLayout.sillTop
  static let sill = OnboardingLayout.sill
  static let window = OnboardingLayout.window
  static let width = OnboardingLayout.width
  static let height = OnboardingLayout.height
  static let wall = OnboardingLayout.wall

  /// Where the flame's holder stands, on the middle of the sill.
  static let holder = GenzRoomPoint(3.0, 1.4, sillTop)

  static let camera = GenzCamera.Home(
    target: GenzRoomPoint(3.0, 1.4, 4.1).scene, yaw: 0, pitch: 0.16, distance: 15.5,
    fieldOfView: 40, yawLimits: -0.1...0.1, pitchLimits: 0.1...0.24)
}

/// What holds the flame. It changes with the stage, so the flame has somewhere that suits its size.
enum FlameHolder: Equatable, Sendable {
  /// A clay saucer with a coal in it.
  case dish
  /// A short candle in the saucer.
  case candle
  /// A little lantern around the candle.
  case lantern
  /// A low brazier with `logs` crossed in it.
  case hearth(logs: Int)

  init(_ stage: FlameStage) {
    switch stage {
    case .ember, .spark: self = .dish
    case .candle, .steady: self = .candle
    case .lantern: self = .lantern
    case .hearth: self = .hearth(logs: 2)
    case .fire: self = .hearth(logs: 3)
    case .beacon, .everglow: self = .hearth(logs: 4)
    }
  }

  /// How far above the sill the flame's foot sits.
  var flameFoot: Float {
    switch self {
    case .dish: 0.2
    case .candle, .lantern: 0.95
    case .hearth: 0.55
    }
  }
}

/// Every number the flame is drawn from, worked out from the streak's growth so size, brightness,
/// colour, sparks and the light on the room all rise together and smoothly.
struct FlameLook: Equatable, Sendable {
  typealias RGB = SIMD3<Float>

  /// The flame's height and width in room units.
  var height: Float
  var width: Float
  /// How strongly its glow shows, 0 to about 1.
  var brightness: Double
  /// How far its halo reaches over the room, in room units.
  var reach: Float
  /// The light it casts: intensity and how far it falls.
  var light: Float
  var lightReach: Float
  /// The two tongues, one per partner, and the core between them.
  var mine: RGB
  var theirs: RGB
  var core: RGB
  /// How many sparks rise from it at once.
  var sparks: Int
  /// How much it flickers, from 0 (steady) up.
  var flicker: Float
  var holder: FlameHolder
  /// True while it rests as an ember: low, glowing, breathing slowly.
  var isEmber: Bool

  /// The most sparks the flame ever keeps, so the scene's pool is sized once.
  static let mostSparks = 14

  /// A pale gold that a young flame burns, and the deep amber a grown one does.
  static let young: RGB = [1, 0.85, 0.55]
  static let grown: RGB = [1, 0.6, 0.24]
  /// Each partner's tint over the flame's own colour: honey for this phone, rose for the partner.
  static let honey: RGB = [1, 0.78, 0.36]
  static let rose: RGB = [1, 0.56, 0.48]
  static let cream: RGB = [1, 0.95, 0.82]
  static let ember: RGB = [1, 0.45, 0.18]

  init(flame: StreakFlame, today: FlameContributions = .init(), reduceMotion: Bool = false) {
    let stage = flame.stage
    holder = FlameHolder(stage)
    isEmber = flame.isEmber
    let growth = Float(flame.growth)
    let warmth = RGB.mix(Self.young, Self.grown, by: growth)
    // Whoever added to it today burns a little brighter, towards cream.
    let lift: (Bool) -> Float = { $0 ? 0.35 : 0 }
    mine = RGB.mix(RGB.mix(warmth, Self.honey, by: 0.55), Self.cream, by: lift(today.mine))
    theirs = RGB.mix(RGB.mix(warmth, Self.rose, by: 0.55), Self.cream, by: lift(today.theirs))
    core = RGB.mix(Self.cream, warmth, by: 0.2)
    let both: Double = today.mine && today.theirs ? 0.1 : 0
    if flame.isEmber {
      height = 0.2
      width = 0.16
      brightness = 0.38
      reach = 1.4
      light = 900
      lightReach = 3
      mine = RGB.mix(Self.ember, Self.honey, by: 0.3)
      theirs = RGB.mix(Self.ember, Self.rose, by: 0.3)
      core = RGB.mix(Self.ember, Self.cream, by: 0.4)
      sparks = 0
      flicker = reduceMotion ? 0.02 : 0.05
    } else {
      height = 0.22 + 2.3 * pow(growth, 1.1)
      width = height * (0.42 + 0.18 * growth)
      brightness = min(0.48 + 0.52 * Double(growth) + both, 1.1)
      reach = 1.3 + 3.4 * growth
      light = 1_600 + 9_400 * growth
      lightReach = 3.2 + 6 * growth
      sparks = min(max(Int(((growth - 0.2) * 18).rounded()), 0), Self.mostSparks)
      flicker = reduceMotion ? 0.04 : 0.1 + 0.06 * growth
    }
    if reduceMotion { sparks = sparks / 2 }
  }
}

/// The once-only moments as values of the time since they began: the celebration's swell and
/// burst of sparks, a rekindling's catch, and a new note's pulse.
enum FlameMoments {
  /// Seconds a celebration or a rekindling lasts.
  static let burstLength = 2.4
  /// Seconds the pulse for a new note lasts: two soft swells.
  static let pulseLength = 2.6
  /// How many sparks a celebration throws, and a rekindling.
  static let celebrationSparks = 26
  static let rekindleSparks = 12

  /// How much brighter and taller the flame stands, from 0 back down to 0.
  static func swell(_ age: Double) -> Double {
    guard age >= 0, age < burstLength else { return 0 }
    let rise = min(age / 0.25, 1)
    let fall = exp(-max(age - 0.25, 0) * 1.8)
    return rise * fall
  }

  /// How far a rekindled flame has caught, from its ember's size (0) to its own (1).
  static func caught(_ age: Double) -> Double {
    OnboardingTimeline.smoother(age / 1.4)
  }

  /// The new note's pulse, 0 to 1, as two swells.
  static func pulse(_ age: Double) -> Double {
    guard age >= 0, age < pulseLength else { return 0 }
    let phase = age / pulseLength
    return pow(sin(phase * 4 * .pi - .pi / 2) * 0.5 + 0.5, 1.5) * (1 - phase * 0.4)
  }
}
