import Foundation
import RealityKit

/// The clips the Nooki room picks from, by what is happening in it. Each is a `CatAction` of the
/// same name, played from the cat's own clip table. Clips stay in place: travel comes from the
/// room.
enum NookiClip: String, CaseIterable, Sendable {
  case idle
  case walk
  case sit
  case sleep
  case crouchWiggle
  case pounce

  /// Whether the cat walks with the rig. When false it travels with the toy hop instead, and the
  /// rig keeps everything else.
  static let walksWithRig = true

  /// How fast a planted paw moves back in the walk clip at normal rate, in the model's metres a
  /// second. Every made cat walks one 0.083 m stride a second with each paw down for 62% of it, so
  /// a planted paw covers the stride in 0.62 s; measured off the hero and the detailed cat it is
  /// 0.125 to 0.128. Travel at this speed keeps paws still on the floor.
  static let pawSpeed: Float = 0.126

  /// How fast the walk clip's feet travel at normal rate, in metres a second in the room.
  static let walkingSpeed: Float = pawSpeed * NookiDiorama.catScale

  private static let fastestWalk: Float = 3

  /// The playback rate that keeps feet from sliding at `speed` metres a second.
  static func walkRate(forTravelAt speed: Float) -> Float {
    min(max(speed / walkingSpeed, 1), fastestWalk)
  }

  /// Which clip a moment of the scene calls for.
  static func choose(frame: NookiFrame, yarn: NookiYarnPlay.Phase, walks: Bool = walksWithRig)
    -> NookiClip
  {
    switch yarn {
    case .watching, .proud:
      return .sit
    case .crouching, .wiggling:
      return .crouchWiggle
    case .chasing, .returning:
      return walks ? .walk : .idle
    case .pouncing:
      return .pounce
    case .resting:
      if frame.walk > 0, frame.walk < 1 { return walks ? .walk : .idle }
      if !frame.eyesOpen { return .sleep }
      return frame.wake >= 0.5 ? .idle : .sit
    }
  }
}
